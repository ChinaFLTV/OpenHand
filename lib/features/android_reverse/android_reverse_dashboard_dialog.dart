import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_safe_scrollbar.dart';
import '../../shared/util/localized_text.dart';
import '../ai/index.dart';
import '../mcp/index.dart';
import '../plugin_service/index.dart';
import 'android_reverse_adb_client.dart';
import 'android_reverse_session_config.dart';
import 'android_reverse_session_controller.dart';
import 'android_reverse_toolchain_diagnostics.dart';

const Duration _kSwitchDuration = Duration(milliseconds: 220);
const Curve _kSwitchInCurve = Curves.easeOutCubic;
const double _kAdbInlineControlHeight = 44;
const double _kIconButtonGap = 8;
const int _kDefaultLogcatLines = 300;
const int _kPackageDumpsysSummaryMaxLines = 160;
const int _kDefaultScreenRecordSeconds = 10;
const int _kMcpRuntimeToolNameLimit = 64;
const int _kMcpToolPreviewLimit = 8;
const int _kMcpToolSearchLimit = 8;
const Duration _kInteractiveShellTimeout = Duration(seconds: 8);
const Duration _kPackageDumpsysTimeout = Duration(seconds: 12);
const Duration _kDeviceSnapshotTimeout = Duration(seconds: 8);
const int _kDeviceSnapshotMaxLines = 80;
const String _kDeviceSnapshotScript = '''
printf '[battery]\\n'
dumpsys battery | grep -E 'level:|status:|temperature:|voltage:|AC powered:|USB powered:|Wireless powered:' || true
printf '[display]\\n'
wm size; wm density
printf '[storage]\\n'
df -h /data /sdcard 2>/dev/null || df /data /sdcard 2>/dev/null || true
printf '[foreground]\\n'
dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -4 || true
printf '[abi]\\n'
getprop ro.product.cpu.abi
getprop ro.product.cpu.abilist
''';
const List<String> _kLogcatLevels = <String>['V', 'D', 'I', 'W', 'E', 'F'];
const List<String> _kAndroidMcpKeywords = <String>[
  'adb',
  'android',
  'apk',
  'aapt',
  'apksigner',
  'apktool',
  'jadx',
  'frida',
  'objection',
  'ida',
  'radare',
  'r2',
  'mitm',
  'proxy',
  'flutter',
  'dart',
  'blutter',
  'doldrums',
  'anything',
  'analyzer',
  'logcat',
  'device',
  'shell',
];
const List<String> _kAndroidRuntimePluginIds = <String>[
  'nodejs',
  'python',
  'pip',
  'playwright',
];
const String _kAndroidMcpToolSearchFallbackQuery =
    'select:adb,android,frida,ida,apktool,jadx,anything-analyzer,flutter';
const String _kAndroidStdioMcpConfigTemplate = '''
{
  "mcpServers": {
    "android-adb": {
      "enabled": true,
      "probeEnabled": true,
      "type": "stdio",
      "transport": "stdio",
      "command": "npx",
      "args": ["-y", "<adb-mcp-package>"]
    }
  }
}''';
const String _kAndroidHttpMcpConfigTemplate = '''
{
  "mcpServers": {
    "ida-pro": {
      "enabled": true,
      "probeEnabled": true,
      "type": "sse",
      "transport": "sse",
      "url": "http://127.0.0.1:<port>/sse"
    }
  }
}''';

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
  toolchain,
  mcpPlugins,
  packages,
  processes,
  logcat,
  frida,
  network,
  staticAnalysis,
  certs,
  crypto,
}

enum _DeviceMenuAction {
  useForPanel,
  copySerial,
  refreshProps,
  listForwards,
  tcpip5555,
  deviceReport,
  screenshot,
  screenRecord,
  root,
  remount,
  reboot,
  disconnect,
}

enum _PackageMenuAction {
  analyze,
  report,
  copyPackage,
  launch,
  forceStop,
  clearData,
  pullApks,
  logcat,
  uninstall,
}

enum _ProcessMenuAction { copyPid, copyName, kill, forceStopPackage, logcatPid }

enum _ToolchainCommandAction { install, update, uninstall, reference }

class _FridaSnippetPreset {
  const _FridaSnippetPreset({
    required this.id,
    required this.assetPath,
    required this.labelZh,
    required this.labelEn,
    required this.descZh,
    required this.descEn,
  });

  final String id;
  final String assetPath;
  final String labelZh;
  final String labelEn;
  final String descZh;
  final String descEn;

  String label(bool isZh) => isZh ? labelZh : labelEn;

  String desc(bool isZh) => isZh ? descZh : descEn;
}

const List<_FridaSnippetPreset> _kFridaSnippetPresets = <_FridaSnippetPreset>[
  _FridaSnippetPreset(
    id: 'java_method',
    assetPath:
        'assets/prompts/android_reverse_expert/snippets/hook_java_method.js',
    labelZh: 'Java 方法',
    labelEn: 'Java method',
    descZh: '入参、返回值、调用栈',
    descEn: 'Args, return value, stack',
  ),
  _FridaSnippetPreset(
    id: 'okhttp',
    assetPath: 'assets/prompts/android_reverse_expert/snippets/hook_okhttp.js',
    labelZh: 'OkHttp',
    labelEn: 'OkHttp',
    descZh: '请求/响应 URL、Header、Body',
    descEn: 'Request/response URL, headers, body',
  ),
  _FridaSnippetPreset(
    id: 'ssl_pinning',
    assetPath:
        'assets/prompts/android_reverse_expert/snippets/hook_ssl_pinning.js',
    labelZh: 'SSL Pinning',
    labelEn: 'SSL Pinning',
    descZh: '常见证书锁定绕过',
    descEn: 'Common pinning bypass',
  ),
  _FridaSnippetPreset(
    id: 'aes_cbc',
    assetPath: 'assets/prompts/android_reverse_expert/snippets/hook_aes_cbc.js',
    labelZh: 'AES/CBC',
    labelEn: 'AES/CBC',
    descZh: 'Cipher doFinal 明文/密文',
    descEn: 'Cipher doFinal plaintext/ciphertext',
  ),
  _FridaSnippetPreset(
    id: 'native_func',
    assetPath:
        'assets/prompts/android_reverse_expert/snippets/hook_native_func.js',
    labelZh: 'Native 函数',
    labelEn: 'Native function',
    descZh: 'JNI/so 入参 hexdump',
    descEn: 'JNI/so args and hexdump',
  ),
  _FridaSnippetPreset(
    id: 'webview',
    assetPath: 'assets/prompts/android_reverse_expert/snippets/hook_webview.js',
    labelZh: 'WebView',
    labelEn: 'WebView',
    descZh: 'loadUrl / evaluateJavascript',
    descEn: 'loadUrl / evaluateJavascript',
  ),
  _FridaSnippetPreset(
    id: 'flutter_dart',
    assetPath:
        'assets/prompts/android_reverse_expert/snippets/hook_flutter_dart.js',
    labelZh: 'Flutter/Dart',
    labelEn: 'Flutter/Dart',
    descZh: '配合 blutter/Doldrums',
    descEn: 'Use with blutter/Doldrums',
  ),
];

extension _TabLabel on _Tab {
  String label(bool isZh) {
    return switch (this) {
      _Tab.devices => isZh ? '设备管理' : 'Devices',
      _Tab.overview => isZh ? '概览' : 'Overview',
      _Tab.toolchain => isZh ? '工具链' : 'Toolchain',
      _Tab.mcpPlugins => isZh ? 'MCP/插件' : 'MCP',
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
    _Tab.toolchain => Icons.construction_rounded,
    _Tab.mcpPlugins => Icons.extension_rounded,
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
  final TextEditingController _wirelessEndpointCtrl = TextEditingController();
  final TextEditingController _forwardLocalCtrl = TextEditingController();
  final TextEditingController _forwardRemoteCtrl = TextEditingController();
  final TextEditingController _logcatFilterCtrl = TextEditingController();
  final TextEditingController _logcatPidCtrl = TextEditingController();
  final TextEditingController _installApkPathCtrl = TextEditingController();
  final TextEditingController _pushLocalCtrl = TextEditingController();
  final TextEditingController _pushRemoteCtrl = TextEditingController();
  final TextEditingController _pullRemoteCtrl = TextEditingController();
  final TextEditingController _pullLocalCtrl = TextEditingController();
  final TextEditingController _fridaScriptCtrl = TextEditingController();
  final TextEditingController _base64Ctrl = TextEditingController();
  final TextEditingController _base64OutCtrl = TextEditingController();
  bool _loadingLogcat = false;
  bool _loadingPackages = false;
  bool _loadingProcesses = false;
  bool _loadingToolchain = false;
  bool _loadingPackageAnalysis = false;
  bool _capturingPackageReport = false;
  bool _runningShell = false;
  bool _runningDeviceAction = false;
  bool _runningStaticQuickScan = false;
  bool _writingNetworkAddon = false;
  bool _writingCertificateArtifacts = false;
  bool _writingMcpArtifacts = false;
  bool _capturingLogcatSnapshot = false;
  bool _loadingDeviceDetails = false;
  bool _savingFridaScript = false;
  bool _logcatPackageFilterEnabled = false;
  String? _selectedDeviceSerial;
  String? _lastDeviceActionOutput;
  String? _logcatError;
  String _logcatLevel = 'V';
  Map<String, String> _deviceProps = const <String, String>{};
  List<String> _forwardRows = const <String>[];
  String? _deviceSnapshotOutput;
  List<String> _packages = const <String>[];
  List<AndroidReverseToolchainProbeResult> _toolchainRows =
      const <AndroidReverseToolchainProbeResult>[];
  List<AndroidProcess> _processes = const <AndroidProcess>[];
  String? _selectedPackageName;
  String? _packageAnalysisOutput;
  String? _selectedFridaSnippetAsset;
  String? _fridaArtifactOutput;
  String? _staticQuickScanOutput;
  String? _logcatArtifactOutput;
  String? _networkAddonOutput;
  String? _certificateArtifactOutput;
  String? _mcpArtifactOutput;
  final _processFilter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller;
    _logcatPackageFilterEnabled = (_ctrl.config.packageName ?? '')
        .trim()
        .isNotEmpty;
    _installApkPathCtrl.text = _ctrl.config.apkPath ?? '';
    _pushRemoteCtrl.text = '/sdcard/Download/';
    _pullRemoteCtrl.text = '/sdcard/Download/';
    _pullLocalCtrl.text = _ctrl.artifactsRootDir;
    _ctrl.addListener(_onControllerChanged);
    _fridaScriptCtrl.addListener(_onFridaScriptChanged);
    _refreshAll();
    unawaited(_refreshToolchain());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _fridaScriptCtrl.removeListener(_onFridaScriptChanged);
    _logcatTimer?.cancel();
    _shellCtrl.dispose();
    _shellOutputCtrl.dispose();
    _wirelessEndpointCtrl.dispose();
    _forwardLocalCtrl.dispose();
    _forwardRemoteCtrl.dispose();
    _logcatFilterCtrl.dispose();
    _logcatPidCtrl.dispose();
    _installApkPathCtrl.dispose();
    _pushLocalCtrl.dispose();
    _pushRemoteCtrl.dispose();
    _pullRemoteCtrl.dispose();
    _pullLocalCtrl.dispose();
    _fridaScriptCtrl.dispose();
    _base64Ctrl.dispose();
    _base64OutCtrl.dispose();
    _processFilter.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onFridaScriptChanged() {
    if (mounted) setState(() {});
  }

  String? get _targetSerial {
    final selected = _selectedDeviceSerial?.trim();
    if (selected != null && selected.isNotEmpty) return selected;
    final configured = _ctrl.config.deviceSerial?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return _ctrl.connectedDevice?.serial;
  }

  void _refreshAll() {
    unawaited(_doRefreshDevices());
    unawaited(_doRefreshPackages());
    unawaited(_doRefreshProcesses());
    unawaited(_refreshDeviceDetails());
  }

  Future<void> _refreshToolchain() async {
    if (_loadingToolchain) return;
    setState(() => _loadingToolchain = true);
    try {
      final rows = await probeAndroidReverseToolchain();
      if (!mounted) return;
      setState(() => _toolchainRows = rows);
    } finally {
      if (mounted) setState(() => _loadingToolchain = false);
    }
  }

  Future<void> _doRefreshDevices() async {
    await _ctrl.refreshDevices();
    if (!mounted) return;
    final selected = _selectedDeviceSerial;
    if (selected != null &&
        !_ctrl.allDevices.any((device) => device.serial == selected)) {
      setState(() => _selectedDeviceSerial = null);
    }
  }

  Future<void> _doRefreshPackages() async {
    if (_loadingPackages) return;
    setState(() => _loadingPackages = true);
    try {
      final pkgs = await _ctrl.listPackages(serial: _targetSerial);
      if (mounted) {
        setState(() {
          _packages = pkgs;
          if (_selectedPackageName != null &&
              !pkgs.contains(_selectedPackageName)) {
            _selectedPackageName = null;
            _packageAnalysisOutput = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loadingPackages = false);
    }
  }

  Future<void> _analyzePackage(String packageName) async {
    if (_loadingPackageAnalysis) return;
    setState(() {
      _selectedPackageName = packageName;
      _loadingPackageAnalysis = true;
    });
    try {
      final pathFuture = _ctrl.getPackagePath(
        packageName,
        serial: _targetSerial,
      );
      final versionFuture = _ctrl.getPackageVersion(
        packageName,
        serial: _targetSerial,
      );
      final launcherFuture = _ctrl.resolveLauncherActivity(
        packageName,
        serial: _targetSerial,
      );
      final dumpsysFuture = _ctrl.shellDetailed(
        'dumpsys package $packageName',
        serial: _targetSerial,
        timeout: _kPackageDumpsysTimeout,
      );
      final path = await pathFuture;
      final version = await versionFuture;
      final launcher = await launcherFuture;
      final dumpsys = await dumpsysFuture;
      if (!mounted) return;
      final isZh = openHandIsChineseLocale(context);
      final summary = _summarizePackageDumpsys(dumpsys.stdout);
      final buf = StringBuffer()
        ..writeln('${isZh ? "包名" : "Package"}: $packageName')
        ..writeln('${isZh ? "安装路径" : "APK path"}: ${path ?? "-"}')
        ..writeln('${isZh ? "版本" : "Version"}: ${version ?? "-"}')
        ..writeln('${isZh ? "启动入口" : "Launcher"}: ${launcher ?? "-"}')
        ..writeln()
        ..writeln(isZh ? 'dumpsys 摘要:' : 'dumpsys summary:')
        ..write(summary.isEmpty ? (isZh ? '(无输出)' : '(no output)') : summary);
      if (dumpsys.timedOut) {
        buf
          ..writeln()
          ..writeln(
            isZh
                ? '(dumpsys 已超时，已展示可用输出)'
                : '(dumpsys timed out; usable output shown)',
          );
      }
      final err = dumpsys.stderr.trim();
      if (!dumpsys.ok && err.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('${isZh ? "错误" : "Error"}: $err');
      }
      setState(() => _packageAnalysisOutput = buf.toString());
    } finally {
      if (mounted) setState(() => _loadingPackageAnalysis = false);
    }
  }

  Future<void> _capturePackageReport(String packageName) async {
    if (_capturingPackageReport) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _selectedPackageName = packageName;
      _capturingPackageReport = true;
    });
    try {
      final result = await _ctrl.capturePackageReportToArtifacts(
        packageName,
        serial: _targetSerial,
      );
      if (!mounted) return;
      setState(() => _packageAnalysisOutput = _formatAdbResult(result));
      if (result.ok || result.partialOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isZh ? '已生成 APP 信息报告工件。' : 'APP report artifacts saved.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _packageAnalysisOutput =
            '${isZh ? "生成 APP 信息报告失败" : "Failed to generate APP report"}: $error';
      });
    } finally {
      if (mounted) setState(() => _capturingPackageReport = false);
    }
  }

  String _summarizePackageDumpsys(String raw) {
    final summary = <String>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final isSectionHeader =
          trimmed == 'requested permissions:' ||
          trimmed == 'install permissions:' ||
          trimmed == 'runtime permissions:' ||
          trimmed == 'PackageSignatures{' ||
          trimmed.startsWith('SigningDetails');
      final isKeyLine =
          trimmed.startsWith('versionCode=') ||
          trimmed.startsWith('versionName=') ||
          trimmed.startsWith('targetSdk=') ||
          trimmed.startsWith('firstInstallTime=') ||
          trimmed.startsWith('lastUpdateTime=') ||
          trimmed.startsWith('signatures=') ||
          trimmed.startsWith('pkgFlags=') ||
          trimmed.startsWith('privateFlags=') ||
          trimmed.startsWith('User 0:');
      final isPermissionLine = trimmed.startsWith('android.permission.');
      if (isSectionHeader || isKeyLine || isPermissionLine) {
        summary.add(trimmed);
      }
      if (summary.length >= _kPackageDumpsysSummaryMaxLines) break;
    }
    if (summary.isEmpty && raw.trim().isNotEmpty) {
      return raw
          .split('\n')
          .map((line) => line.trimRight())
          .where((line) => line.trim().isNotEmpty)
          .take(_kPackageDumpsysSummaryMaxLines)
          .join('\n');
    }
    return summary.join('\n');
  }

  Future<void> _doRefreshProcesses() async {
    if (_loadingProcesses) return;
    setState(() => _loadingProcesses = true);
    try {
      final filter = _processFilter.text.trim().isEmpty
          ? null
          : _processFilter.text.trim();
      final procs = await _ctrl.refreshProcesses(
        filterName: filter,
        serial: _targetSerial,
      );
      if (mounted) setState(() => _processes = procs);
    } finally {
      if (mounted) setState(() => _loadingProcesses = false);
    }
  }

  Future<void> _refreshDeviceDetails() async {
    if (_loadingDeviceDetails) return;
    final serial = _targetSerial;
    if (serial == null || serial.isEmpty) {
      if (mounted) {
        setState(() {
          _deviceProps = const <String, String>{};
          _forwardRows = const <String>[];
          _deviceSnapshotOutput = null;
        });
      }
      return;
    }
    setState(() => _loadingDeviceDetails = true);
    try {
      final isZh = openHandIsChineseLocale(context);
      final propsFuture = _ctrl.getProperties(serial: serial);
      final forwardsFuture = _ctrl.listForwards(serial: serial);
      final snapshotFuture = _ctrl.shellDetailed(
        _kDeviceSnapshotScript,
        serial: serial,
        timeout: _kDeviceSnapshotTimeout,
      );
      final props = await propsFuture;
      final forwards = await forwardsFuture;
      final snapshot = await snapshotFuture;
      if (!mounted) return;
      setState(() {
        _deviceProps = props;
        _forwardRows = (forwards ?? '')
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false);
        _deviceSnapshotOutput = _formatDeviceSnapshot(snapshot, isZh);
      });
    } finally {
      if (mounted) setState(() => _loadingDeviceDetails = false);
    }
  }

  String? _formatDeviceSnapshot(AdbCommandResult result, bool isZh) {
    final lines = result.stdout
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .take(_kDeviceSnapshotMaxLines)
        .toList(growable: false);
    final stderr = result.stderr.trim();
    if (lines.isEmpty && stderr.isEmpty) return null;
    final buffer = StringBuffer();
    if (lines.isNotEmpty) {
      buffer.write(lines.join('\n'));
    }
    if (result.timedOut) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(
        isZh
            ? '(设备现场读取超时，已展示可用输出)'
            : '(snapshot timed out; usable output shown)',
      );
    }
    if (!result.ok && stderr.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write('${isZh ? "错误" : "Error"}: $stderr');
    }
    return buffer.toString().trimRight();
  }

  Future<void> _fetchLogcat() async {
    if (_loadingLogcat) return;
    setState(() {
      _loadingLogcat = true;
      _logcatError = null;
    });
    try {
      final isZh = openHandIsChineseLocale(context);
      final tag = _logcatFilterCtrl.text.trim();
      final explicitPid = _logcatPidCtrl.text.trim();
      final packageName = _logcatPackageFilterEnabled
          ? _logcatPackageTarget()
          : null;
      var pid = RegExp(r'^\d+$').hasMatch(explicitPid) ? explicitPid : null;
      String? filterNotice;
      if (pid == null && packageName != null) {
        pid = await _ctrl.pidOfPackage(packageName, serial: _targetSerial);
        if (pid == null || pid.trim().isEmpty) {
          filterNotice = isZh
              ? '目标包未运行或无法解析 PID，已按当前等级读取全局 Logcat。'
              : 'Target package is not running or PID was unavailable; loaded global logcat with the selected level.';
        }
      } else if (explicitPid.isNotEmpty && pid == null) {
        filterNotice = isZh
            ? 'PID 只能填写数字，已忽略该 PID 过滤。'
            : 'PID must be numeric; PID filter was ignored.';
      }
      final result = await _ctrl.logcatDetailed(
        lines: _kDefaultLogcatLines,
        tag: tag.isEmpty ? null : tag,
        level: _logcatLevel,
        pid: pid,
        serial: _targetSerial,
      );
      if (mounted) {
        final lines = result.stdout
            .split('\n')
            .map(_sanitizeLogcatLine)
            .where(_hasVisibleLogcatText)
            .toList(growable: false);
        final err = result.stderr.trim();
        setState(() {
          _logcatLines
            ..clear()
            ..addAll(lines);
          if (lines.isNotEmpty && result.timedOut) {
            _logcatError = isZh
                ? 'Logcat 读取超时，已展示可用输出。'
                : 'Logcat timed out; usable output is shown.';
          } else if (lines.isNotEmpty && filterNotice != null) {
            _logcatError = filterNotice;
          } else if (lines.isNotEmpty) {
            _logcatError = null;
          } else if (err.isNotEmpty) {
            _logcatError = err;
          } else {
            _logcatError = isZh
                ? '没有读取到 Logcat 输出。请确认设备在线，或清空 Tag 过滤后重试。'
                : 'No Logcat output was read. Check the device or clear the tag filter and retry.';
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _logcatLines.clear();
        _logcatError = '$error';
      });
    } finally {
      if (mounted) setState(() => _loadingLogcat = false);
    }
  }

  Future<void> _clearLogcat() async {
    if (_loadingLogcat) return;
    setState(() {
      _loadingLogcat = true;
      _logcatError = null;
    });
    try {
      final result = await _ctrl.clearLogcatDetailed(serial: _targetSerial);
      if (!mounted) return;
      final isZh = openHandIsChineseLocale(context);
      setState(() {
        _logcatLines.clear();
        _logcatError = result.ok
            ? (isZh ? '已清空设备 Logcat。' : 'Device logcat was cleared.')
            : _formatAdbResult(result);
      });
    } finally {
      if (mounted) setState(() => _loadingLogcat = false);
    }
  }

  String _sanitizeLogcatLine(String line) {
    return line
        .replaceAll(
          RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'),
          '',
        )
        .trimRight();
  }

  bool _hasVisibleLogcatText(String line) {
    return line.replaceAll(RegExp(r'\s+'), '').isNotEmpty;
  }

  Future<void> _saveLogcatSnapshot() async {
    if (_logcatLines.isEmpty) return;
    final tag = _logcatFilterCtrl.text.trim();
    final pid = _logcatPidCtrl.text.trim();
    final packageName = _logcatPackageFilterEnabled
        ? _logcatPackageTarget()
        : null;
    final saved = await _ctrl.appendLogcatLines(
      _logcatLines,
      tag: tag.isEmpty ? null : tag,
      level: _logcatLevel,
      packageName: packageName,
      pid: pid.isEmpty ? null : pid,
      serial: _targetSerial,
    );
    if (!mounted) return;
    final isZh = openHandIsChineseLocale(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved > 0
              ? (isZh
                    ? '已保存 $saved 行到 ${_ctrl.logcatJsonlPath}'
                    : 'Saved $saved lines to ${_ctrl.logcatJsonlPath}')
              : (isZh ? '没有可保存的 Logcat 行。' : 'No logcat lines were saved.'),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _captureLogcatArtifactSnapshot() async {
    if (_capturingLogcatSnapshot) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _capturingLogcatSnapshot = true;
      _logcatArtifactOutput = null;
    });
    try {
      final tag = _logcatFilterCtrl.text.trim();
      final explicitPid = _logcatPidCtrl.text.trim();
      final packageName = _logcatPackageFilterEnabled
          ? _logcatPackageTarget()
          : null;
      var pid = RegExp(r'^\d+$').hasMatch(explicitPid) ? explicitPid : null;
      if (pid == null && packageName != null) {
        pid = await _ctrl.pidOfPackage(packageName, serial: _targetSerial);
      }
      final result = await _ctrl.captureLogcatSnapshotToArtifacts(
        tag: tag.isEmpty ? null : tag,
        level: _logcatLevel,
        pid: pid,
        packageName: packageName,
        serial: _targetSerial,
        lines: _kDefaultLogcatLines,
      );
      if (!mounted) return;
      setState(() {
        _logcatArtifactOutput = _formatAdbResult(result);
        if (!result.ok && !result.partialOk) {
          _logcatError = _logcatArtifactOutput;
        }
      });
      if (result.ok || result.partialOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isZh ? '已生成 Logcat 快照工件。' : 'Logcat snapshot artifacts saved.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _logcatArtifactOutput =
            '${isZh ? "生成 Logcat 快照失败" : "Failed to capture Logcat snapshot"}: $error';
        _logcatError = _logcatArtifactOutput;
      });
    } finally {
      if (mounted) setState(() => _capturingLogcatSnapshot = false);
    }
  }

  Future<void> _runStaticQuickScan() async {
    if (_runningStaticQuickScan) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _runningStaticQuickScan = true;
      _staticQuickScanOutput = null;
    });
    try {
      final result = await _ctrl.runStaticQuickScan(
        apkPath: _ctrl.config.apkPath,
        packageName: _logcatPackageTarget(),
      );
      if (!mounted) return;
      setState(() => _staticQuickScanOutput = _formatAdbResult(result));
      if (!result.ok && !result.hasUsableStdout) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isZh
                  ? '静态扫描失败，已展示错误输出。'
                  : 'Static scan failed. Error output is shown.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _staticQuickScanOutput =
            '${isZh ? "静态扫描失败" : "Static scan failed"}: $error';
      });
    } finally {
      if (mounted) setState(() => _runningStaticQuickScan = false);
    }
  }

  Future<void> _ensureMitmproxyAddon() async {
    if (_writingNetworkAddon) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() => _writingNetworkAddon = true);
    try {
      final addonPath = await _ctrl.ensureMitmproxyJsonlAddon();
      if (!mounted) return;
      final command =
          'OPENHAND_NETWORK_JSONL=${_shellQuote(_ctrl.networkJsonlPath)} '
          'mitmdump -p 8080 -s ${_shellQuote(addonPath)} '
          '-w ${_shellQuote('${_ctrl.networkDir}/flows.mitm')}';
      setState(() {
        _networkAddonOutput = [
          isZh
              ? '已生成 mitmproxy JSONL addon:'
              : 'Generated mitmproxy JSONL addon:',
          addonPath,
          '',
          isZh ? '启动命令:' : 'Start command:',
          command,
          '',
          'JSONL: ${_ctrl.networkJsonlPath}',
        ].join('\n');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _networkAddonOutput =
            '${isZh ? "生成 mitmproxy addon 失败" : "Failed to generate mitmproxy addon"}: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isZh
                ? '生成 mitmproxy addon 失败。'
                : 'Failed to generate mitmproxy addon.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _writingNetworkAddon = false);
    }
  }

  Future<void> _ensureCertificateArtifacts() async {
    if (_writingCertificateArtifacts) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() => _writingCertificateArtifacts = true);
    try {
      final output = await _ctrl.ensureCertificateArtifacts(
        packageName: _logcatPackageTarget(),
      );
      if (!mounted) return;
      setState(() => _certificateArtifactOutput = output);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _certificateArtifactOutput =
            '${isZh ? "生成证书工件失败" : "Failed to generate certificate artifacts"}: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isZh ? '生成证书工件失败。' : 'Failed to generate certificate artifacts.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _writingCertificateArtifacts = false);
    }
  }

  Future<void> _ensureMcpLinkageArtifacts() async {
    if (_writingMcpArtifacts) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() => _writingMcpArtifacts = true);
    try {
      final output = await _ctrl.ensureMcpLinkageArtifacts();
      if (!mounted) return;
      setState(() => _mcpArtifactOutput = output);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _mcpArtifactOutput =
            '${isZh ? "生成 MCP 联动工件失败" : "Failed to generate MCP linkage artifacts"}: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isZh
                ? '生成 MCP 联动工件失败。'
                : 'Failed to generate MCP linkage artifacts.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _writingMcpArtifacts = false);
    }
  }

  Future<void> _loadFridaSnippet(_FridaSnippetPreset preset) async {
    try {
      final script = await rootBundle.loadString(preset.assetPath);
      if (!mounted) return;
      _selectedFridaSnippetAsset = preset.assetPath;
      _fridaScriptCtrl.text = script.trimRight();
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      final isZh = openHandIsChineseLocale(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isZh
                ? '加载 Frida snippet 失败：$error'
                : 'Failed to load Frida snippet: $error',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _saveFridaScriptArtifact() async {
    if (_savingFridaScript) return;
    final script = _fridaScriptCtrl.text;
    if (script.trim().isEmpty) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() => _savingFridaScript = true);
    try {
      final result = await _ctrl.saveFridaScriptToArtifacts(
        script: script,
        presetAssetPath: _selectedFridaSnippetAsset,
        packageName: _logcatPackageTarget(),
      );
      if (!mounted) return;
      setState(() => _fridaArtifactOutput = _formatAdbResult(result));
      if (result.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isZh ? '已保存 Frida 脚本工件。' : 'Frida script artifact saved.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _fridaArtifactOutput =
            '${isZh ? "保存 Frida 脚本失败" : "Failed to save Frida script"}: $error';
      });
    } finally {
      if (mounted) setState(() => _savingFridaScript = false);
    }
  }

  Future<void> _runShell() async {
    final rawCmd = _shellCtrl.text.trim();
    final cmd = _normalizeAdbShellInput(rawCmd);
    if (cmd.isEmpty || _runningShell) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _runningShell = true;
      _shellOutputCtrl.text = isZh ? '执行中：$cmd' : 'Running: $cmd';
    });
    try {
      final result = await _ctrl.shellDetailed(
        cmd,
        serial: _targetSerial,
        timeout: _kInteractiveShellTimeout,
      );
      if (!mounted) return;
      final output = _formatAdbResult(result);
      setState(() {
        _shellOutputCtrl.text = output;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _shellOutputCtrl.text =
            '${openHandIsChineseLocale(context) ? "执行失败" : "Run failed"}: $error';
      });
    } finally {
      if (mounted) setState(() => _runningShell = false);
    }
  }

  String _formatAdbResult(AdbCommandResult result) {
    final isZh = openHandIsChineseLocale(context);
    final buffer = StringBuffer()
      ..writeln('\$ ${result.commandLine}')
      ..writeln('${isZh ? "退出码" : "exit"}: ${result.exitCode}');
    if (result.partialOk) {
      buffer.writeln(
        isZh
            ? '状态: 命令超时，但已保留可用输出；请优先采纳输出并减少重复重试。'
            : 'status: timed out with usable output; prefer the output and avoid repeating the same command.',
      );
    }
    final stdout = result.stdout.trim();
    final stderr = result.stderr.trim();
    if (stdout.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(stdout);
    }
    if (stderr.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(isZh ? 'stderr:' : 'stderr:')
        ..writeln(stderr);
    }
    if (stdout.isEmpty && stderr.isEmpty) {
      buffer
        ..writeln()
        ..write(isZh ? '(命令无输出)' : '(no output)');
    }
    return buffer.toString().trimRight();
  }

  Future<void> _runDeviceAction(
    Future<AdbCommandResult> Function() action,
  ) async {
    if (_runningDeviceAction) return;
    setState(() => _runningDeviceAction = true);
    try {
      final result = await action();
      if (!mounted) return;
      setState(() => _lastDeviceActionOutput = _formatAdbResult(result));
      await _doRefreshDevices();
      await _refreshDeviceDetails();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lastDeviceActionOutput =
            '${openHandIsChineseLocale(context) ? "执行失败" : "Run failed"}: $error';
      });
    } finally {
      if (mounted) setState(() => _runningDeviceAction = false);
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
          context
              .watch<AiSessionController>()
              .sessions
              .where((s) => s.id == widget.sessionId)
              .firstOrNull
              ?.metadata['android_reverse_config'],
        ) ??
        _ctrl.config;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
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
    final activeDevice = _selectedDeviceSerial == null
        ? device
        : _ctrl.allDevices
              .where((item) => item.serial == _selectedDeviceSerial)
              .firstOrNull;
    final statusColor = !running
        ? cs.outline
        : activeDevice == null
        ? cs.error
        : cs.primary;
    final statusLabel = !running
        ? (isZh ? '已停止' : 'stopped')
        : activeDevice == null
        ? (isZh ? '无设备' : 'no device')
        : activeDevice.model ?? activeDevice.serial;
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
          const SizedBox(width: _kIconButtonGap),
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
        children: _Tab.values
            .map((tab) {
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
                      if (tab == _Tab.toolchain && _toolchainRows.isEmpty) {
                        _refreshToolchain();
                      }
                      if (tab == _Tab.mcpPlugins && _toolchainRows.isEmpty) {
                        _refreshToolchain();
                      }
                    },
                    icon: Icon(tab.icon, size: 14),
                    label: Text(
                      tab.label(isZh),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
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
      _Tab.toolchain => _buildToolchainTab(cs, theme, isZh),
      _Tab.mcpPlugins => _buildMcpPluginsTab(cs, theme, isZh),
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
              if (_targetSerial != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    '${isZh ? "当前目标" : "Target"}: $_targetSerial',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () {
                  _refreshAll();
                },
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final list = _buildDeviceList(devices, cs, theme, isZh);
              final details = _buildDeviceDetailsPanel(cs, theme, isZh);
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [
                    Expanded(child: list),
                    Divider(height: 1, color: cs.outlineVariant),
                    SizedBox(height: 220, child: details),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 6, child: list),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  Expanded(flex: 5, child: details),
                ],
              );
            },
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: _kAdbInlineControlHeight,
                      child: TextField(
                        controller: _shellCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: isZh ? 'adb shell 命令' : 'adb shell command',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        style: const TextStyle(fontFamily: 'monospace'),
                        onSubmitted: (_) => _runShell(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: _kAdbInlineControlHeight,
                    child: FilledButton.icon(
                      onPressed: _runningShell ? null : _runShell,
                      icon: _runningShell
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 16),
                      label: Text(isZh ? '执行' : 'Run'),
                    ),
                  ),
                ],
              ),
              if (_shellOutputCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 8),
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

  Widget _buildDeviceList(
    List<AdbDevice> devices,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    if (devices.isEmpty) {
      return Center(
        child: Text(
          isZh
              ? '未找到设备。请连接 Android 设备或启动模拟器后刷新。'
              : 'No devices found. Connect a device or start an emulator, then refresh.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    return OpenHandSafeScrollbar(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: devices.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: cs.outlineVariant),
        itemBuilder: (_, i) {
          final d = devices[i];
          final selected = _targetSerial == d.serial;
          return GestureDetector(
            onSecondaryTapDown: (details) =>
                _showDeviceMenu(d, details.globalPosition),
            onDoubleTap: () => _showDeviceMenu(d, null),
            child: ListTile(
              selected: selected,
              selectedTileColor: cs.primaryContainer.withValues(alpha: 0.22),
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
              trailing: Chip(
                label: Text(
                  d.isOnline
                      ? (isZh ? '在线' : 'online')
                      : (isZh ? '异常' : d.state),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: d.isOnline ? cs.primary : cs.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                backgroundColor:
                    (d.isOnline ? cs.primaryContainer : cs.errorContainer)
                        .withValues(alpha: 0.42),
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
              ),
              onTap: () {
                setState(() => _selectedDeviceSerial = d.serial);
                unawaited(_refreshDeviceDetails());
                unawaited(_doRefreshPackages());
                unawaited(_doRefreshProcesses());
              },
              dense: true,
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeviceDetailsPanel(ColorScheme cs, ThemeData theme, bool isZh) {
    final serial = _targetSerial;
    final device = serial == null
        ? null
        : _ctrl.allDevices.where((item) => item.serial == serial).firstOrNull;
    final snapshot = _deviceSnapshotOutput?.trim();
    final propItems = <(String, String)>[
      (
        isZh ? '系统版本' : 'Android',
        _deviceProps['ro.build.version.release'] ?? '-',
      ),
      (isZh ? 'SDK' : 'SDK', _deviceProps['ro.build.version.sdk'] ?? '-'),
      (isZh ? '品牌' : 'Brand', _deviceProps['ro.product.brand'] ?? '-'),
      (isZh ? '设备' : 'Device', _deviceProps['ro.product.device'] ?? '-'),
      (
        isZh ? '指纹' : 'Fingerprint',
        _deviceProps['ro.build.fingerprint'] ?? '-',
      ),
    ];
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isZh ? '设备操作' : 'Device actions',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_loadingDeviceDetails)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (serial == null)
            _InfoCard(
              cs: cs,
              theme: theme,
              icon: Icons.info_outline_rounded,
              text: isZh
                  ? '请选择一个在线设备，或通过无线 ADB 连接设备。'
                  : 'Select an online device or connect one through wireless ADB.',
            )
          else ...[
            _monospaceCard(
              cs,
              [
                device?.model ?? serial,
                serial,
                if (device?.product != null) device!.product!,
              ].join('\n'),
            ),
            const SizedBox(height: 10),
            for (final item in propItems)
              _DeviceInfoRow(label: item.$1, value: item.$2, colorScheme: cs),
            if (snapshot != null && snapshot.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isZh ? '现场快照' : 'Field snapshot',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    tooltip: isZh ? '复制现场快照' : 'Copy field snapshot',
                    onPressed: () => _copyText(snapshot),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _monospaceCard(cs, snapshot),
            ],
          ],
          const SizedBox(height: 14),
          Text(
            isZh ? '无线 ADB' : 'Wireless ADB',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: TextField(
                    controller: _wirelessEndpointCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '192.168.1.10:5555',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _connectWirelessDevice(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: _kAdbInlineControlHeight,
                child: FilledButton.tonalIcon(
                  onPressed: _runningDeviceAction
                      ? null
                      : _connectWirelessDevice,
                  icon: const Icon(Icons.link_rounded, size: 16),
                  label: Text(isZh ? '连接' : 'Connect'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SmallActionButton(
                icon: Icons.link_off_rounded,
                label: isZh ? '断开当前' : 'Disconnect',
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () => _runDeviceAction(() => _ctrl.disconnect(serial)),
              ),
              _SmallActionButton(
                icon: Icons.restart_alt_rounded,
                label: isZh ? '重启' : 'Reboot',
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () =>
                          _runDeviceAction(() => _ctrl.reboot(serial: serial)),
              ),
              _SmallActionButton(
                icon: Icons.admin_panel_settings_rounded,
                label: 'root',
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () => _runDeviceAction(() => _ctrl.root(serial: serial)),
              ),
              _SmallActionButton(
                icon: Icons.storage_rounded,
                label: 'remount',
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () =>
                          _runDeviceAction(() => _ctrl.remount(serial: serial)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            isZh ? '端口转发' : 'Port forwarding',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: TextField(
                    controller: _forwardLocalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isZh ? '本地端口' : 'local',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: TextField(
                    controller: _forwardRemoteCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isZh ? '设备端口' : 'remote',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: _kAdbInlineControlHeight,
                child: FilledButton.tonalIcon(
                  onPressed: serial == null || _runningDeviceAction
                      ? null
                      : _addForward,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(isZh ? '添加' : 'Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_forwardRows.isEmpty)
            Text(
              isZh ? '暂无端口转发' : 'No active forwards',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in _forwardRows)
                  _ForwardRow(
                    row: row,
                    colorScheme: cs,
                    onRemove: _runningDeviceAction
                        ? null
                        : () => _removeForwardFromRow(row),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _runningDeviceAction
                        ? null
                        : () => _runDeviceAction(
                            () => _ctrl
                                .removeAllForwards(serial: serial)
                                .then(
                                  (ok) => AdbCommandResult(
                                    args: const <String>[
                                      'forward',
                                      '--remove-all',
                                    ],
                                    exitCode: ok ? 0 : 1,
                                    stdout: ok ? 'removed all forwards' : '',
                                    stderr: ok ? '' : 'remove-all failed',
                                  ),
                                ),
                          ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    label: Text(isZh ? '移除全部转发' : 'Remove all forwards'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          Text(
            isZh ? '文件 / APK' : 'Files / APK',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          _buildPathActionRow(
            primaryController: _installApkPathCtrl,
            primaryHint: isZh ? '本地 APK 路径' : 'local APK path',
            icon: Icons.install_mobile_rounded,
            label: isZh ? '安装' : 'Install',
            onPressed: serial == null || _runningDeviceAction
                ? null
                : _installApkFromPanel,
          ),
          const SizedBox(height: 8),
          _buildPathActionRow(
            primaryController: _pushLocalCtrl,
            primaryHint: isZh ? '本地路径' : 'local path',
            secondaryController: _pushRemoteCtrl,
            secondaryHint: isZh ? '设备路径' : 'remote path',
            icon: Icons.upload_file_rounded,
            label: 'push',
            onPressed: serial == null || _runningDeviceAction
                ? null
                : _pushFileFromPanel,
          ),
          const SizedBox(height: 8),
          _buildPathActionRow(
            primaryController: _pullRemoteCtrl,
            primaryHint: isZh ? '设备路径' : 'remote path',
            secondaryController: _pullLocalCtrl,
            secondaryHint: isZh ? '本地目录 / 文件' : 'local dir / file',
            icon: Icons.download_rounded,
            label: 'pull',
            onPressed: serial == null || _runningDeviceAction
                ? null
                : _pullFileFromPanel,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SmallActionButton(
                icon: Icons.battery_charging_full_rounded,
                label: isZh ? '电池' : 'Battery',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('dumpsys battery'),
              ),
              _SmallActionButton(
                icon: Icons.aspect_ratio_rounded,
                label: isZh ? '屏幕' : 'Display',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('wm size; wm density'),
              ),
              _SmallActionButton(
                icon: Icons.home_rounded,
                label: 'HOME',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('input keyevent KEYCODE_HOME'),
              ),
              _SmallActionButton(
                icon: Icons.arrow_back_rounded,
                label: isZh ? '返回' : 'Back',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('input keyevent KEYCODE_BACK'),
              ),
              _SmallActionButton(
                icon: Icons.view_carousel_rounded,
                label: isZh ? '最近任务' : 'Recents',
                onPressed: serial == null
                    ? null
                    : () =>
                          _runShellPreset('input keyevent KEYCODE_APP_SWITCH'),
              ),
              _SmallActionButton(
                icon: Icons.screenshot_monitor_rounded,
                label: isZh ? '截屏' : 'Screenshot',
                onPressed: serial == null
                    ? null
                    : () => _runDeviceAction(
                        () => _ctrl.captureScreenshotToArtifacts(
                          serial: _targetSerial,
                        ),
                      ),
              ),
              _SmallActionButton(
                icon: Icons.radio_button_checked_rounded,
                label: isZh
                    ? '录屏 ${_kDefaultScreenRecordSeconds}s'
                    : 'Record ${_kDefaultScreenRecordSeconds}s',
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () => _runDeviceAction(
                        () => _ctrl.screenRecordToArtifacts(
                          serial: _targetSerial,
                        ),
                      ),
              ),
              _SmallActionButton(
                icon: Icons.delete_sweep_rounded,
                label: isZh ? '清 Logcat' : 'Clear logcat',
                onPressed: serial == null
                    ? null
                    : () => _runDeviceAction(
                        () => _ctrl.clearLogcatDetailed(serial: _targetSerial),
                      ),
              ),
              _SmallActionButton(
                icon: Icons.wifi_tethering_rounded,
                label: 'tcpip 5555',
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () => _runDeviceAction(
                        () => _ctrl.tcpip(5555, serial: _targetSerial),
                      ),
              ),
              _SmallActionButton(
                icon: Icons.settings_rounded,
                label: isZh ? '系统设置' : 'Settings',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('settings list global | head -80'),
              ),
              _SmallActionButton(
                icon: Icons.fact_check_rounded,
                label: isZh ? '现场报告' : 'Report',
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () => _runDeviceAction(
                        () => _ctrl.captureDeviceReportToArtifacts(
                          serial: _targetSerial,
                        ),
                      ),
              ),
              _SmallActionButton(
                icon: Icons.hub_rounded,
                label: isZh ? '网络地址' : 'IP addr',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('ip addr show | grep -E "inet "'),
              ),
            ],
          ),
          if (_lastDeviceActionOutput != null &&
              _lastDeviceActionOutput!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _monospaceCard(cs, _lastDeviceActionOutput!),
          ],
        ],
      ),
    );
  }

  Future<void> _connectWirelessDevice() async {
    final endpoint = _wirelessEndpointCtrl.text.trim();
    if (endpoint.isEmpty) return;
    await _runDeviceAction(() => _ctrl.connect(endpoint));
  }

  Future<void> _addForward() async {
    final local = int.tryParse(_forwardLocalCtrl.text.trim());
    final remote = int.tryParse(_forwardRemoteCtrl.text.trim());
    if (local == null || remote == null || local <= 0 || remote <= 0) return;
    await _runDeviceAction(
      () => _ctrl.forwardPortDetailed(local, remote, serial: _targetSerial),
    );
  }

  Future<void> _removeForwardFromRow(String row) async {
    final match = RegExp(r'tcp:(\d+)').firstMatch(row);
    final local = int.tryParse(match?.group(1) ?? '');
    if (local == null) return;
    await _runDeviceAction(
      () => _ctrl.removeForwardDetailed(local, serial: _targetSerial),
    );
  }

  Future<void> _runShellPreset(String command) async {
    _shellCtrl.text = command;
    await _runShell();
  }

  Future<void> _installApkFromPanel() async {
    final path = _installApkPathCtrl.text.trim();
    if (path.isEmpty) return;
    await _runDeviceAction(
      () => _ctrl.installApkDetailed(path, serial: _targetSerial),
    );
    await _doRefreshPackages();
  }

  Future<void> _pushFileFromPanel() async {
    final local = _pushLocalCtrl.text.trim();
    final remote = _pushRemoteCtrl.text.trim();
    if (local.isEmpty || remote.isEmpty) return;
    await _runDeviceAction(
      () => _ctrl.pushDetailed(local, remote, serial: _targetSerial),
    );
  }

  Future<void> _pullFileFromPanel() async {
    final remote = _pullRemoteCtrl.text.trim();
    final local = _pullLocalCtrl.text.trim();
    if (remote.isEmpty || local.isEmpty) return;
    await _runDeviceAction(
      () => _ctrl.pullDetailed(remote, local, serial: _targetSerial),
    );
  }

  Future<void> _showDeviceMenu(AdbDevice device, Offset? globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final center = overlay.size.center(Offset.zero);
    final position = globalPosition ?? overlay.localToGlobal(center);
    final selected = await showMenu<_DeviceMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _DeviceMenuAction.useForPanel,
          child: Text(
            openHandIsChineseLocale(context) ? '设为面板目标' : 'Use for panel',
          ),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.copySerial,
          child: Text(
            openHandIsChineseLocale(context) ? '复制序列号' : 'Copy serial',
          ),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.refreshProps,
          child: Text(
            openHandIsChineseLocale(context)
                ? '刷新属性 / 现场'
                : 'Refresh properties / snapshot',
          ),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.listForwards,
          child: Text(
            openHandIsChineseLocale(context) ? '查看端口转发' : 'List forwards',
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _DeviceMenuAction.tcpip5555,
          child: Text('adb tcpip 5555'),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.deviceReport,
          child: Text(
            openHandIsChineseLocale(context)
                ? '生成现场报告'
                : 'Generate field report',
          ),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.screenshot,
          child: Text(
            openHandIsChineseLocale(context) ? '截屏到工件目录' : 'Capture screenshot',
          ),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.screenRecord,
          child: Text(
            openHandIsChineseLocale(context)
                ? '录屏 $_kDefaultScreenRecordSeconds 秒到工件目录'
                : 'Record $_kDefaultScreenRecordSeconds seconds',
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _DeviceMenuAction.root,
          child: Text('adb root'),
        ),
        const PopupMenuItem(
          value: _DeviceMenuAction.remount,
          child: Text('adb remount'),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.reboot,
          child: Text(openHandIsChineseLocale(context) ? '重启设备' : 'Reboot'),
        ),
        PopupMenuItem(
          value: _DeviceMenuAction.disconnect,
          child: Text(openHandIsChineseLocale(context) ? '断开连接' : 'Disconnect'),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case _DeviceMenuAction.useForPanel:
        setState(() => _selectedDeviceSerial = device.serial);
        await _refreshDeviceDetails();
        await _doRefreshPackages();
        await _doRefreshProcesses();
      case _DeviceMenuAction.copySerial:
        await _copyText(device.serial);
      case _DeviceMenuAction.refreshProps:
        setState(() => _selectedDeviceSerial = device.serial);
        await _refreshDeviceDetails();
      case _DeviceMenuAction.listForwards:
        setState(() => _selectedDeviceSerial = device.serial);
        await _refreshDeviceDetails();
      case _DeviceMenuAction.tcpip5555:
        setState(() => _selectedDeviceSerial = device.serial);
        await _runDeviceAction(() => _ctrl.tcpip(5555, serial: device.serial));
      case _DeviceMenuAction.deviceReport:
        setState(() => _selectedDeviceSerial = device.serial);
        await _runDeviceAction(
          () => _ctrl.captureDeviceReportToArtifacts(serial: device.serial),
        );
      case _DeviceMenuAction.screenshot:
        setState(() => _selectedDeviceSerial = device.serial);
        await _runDeviceAction(
          () => _ctrl.captureScreenshotToArtifacts(serial: device.serial),
        );
      case _DeviceMenuAction.screenRecord:
        setState(() => _selectedDeviceSerial = device.serial);
        await _runDeviceAction(
          () => _ctrl.screenRecordToArtifacts(serial: device.serial),
        );
      case _DeviceMenuAction.root:
        await _runDeviceAction(() => _ctrl.root(serial: device.serial));
      case _DeviceMenuAction.remount:
        await _runDeviceAction(() => _ctrl.remount(serial: device.serial));
      case _DeviceMenuAction.reboot:
        await _runDeviceAction(() => _ctrl.reboot(serial: device.serial));
      case _DeviceMenuAction.disconnect:
        await _runDeviceAction(() => _ctrl.disconnect(device.serial));
    }
  }

  Future<void> _showPackageMenu(
    String packageName,
    Offset? globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final center = overlay.size.center(Offset.zero);
    final position = globalPosition ?? overlay.localToGlobal(center);
    final isZh = openHandIsChineseLocale(context);
    final selected = await showMenu<_PackageMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _PackageMenuAction.analyze,
          child: Text(isZh ? '分析 APP 信息' : 'Analyze app info'),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.report,
          child: Text(isZh ? '生成 APP 信息报告' : 'Generate app report'),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.copyPackage,
          child: Text(isZh ? '复制包名' : 'Copy package name'),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.logcat,
          child: Text(isZh ? '按此包过滤 Logcat' : 'Filter logcat by package'),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.pullApks,
          child: Text(isZh ? '拉取 APK 到工件目录' : 'Pull APKs to artifacts'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _PackageMenuAction.launch,
          child: Text(isZh ? '启动 APP' : 'Launch app'),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.forceStop,
          child: Text(isZh ? '强制停止' : 'Force stop'),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.clearData,
          child: Text(isZh ? '清除数据...' : 'Clear data...'),
        ),
        PopupMenuItem(
          value: _PackageMenuAction.uninstall,
          child: Text(isZh ? '卸载...' : 'Uninstall...'),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    await _handlePackageAction(packageName, selected);
  }

  Future<void> _handlePackageAction(
    String packageName,
    _PackageMenuAction action,
  ) async {
    final isZh = openHandIsChineseLocale(context);
    switch (action) {
      case _PackageMenuAction.analyze:
        await _analyzePackage(packageName);
      case _PackageMenuAction.report:
        await _capturePackageReport(packageName);
      case _PackageMenuAction.copyPackage:
        await _copyText(packageName);
      case _PackageMenuAction.logcat:
        setState(() {
          _selectedPackageName = packageName;
          _logcatPackageFilterEnabled = true;
          _logcatPidCtrl.clear();
          _currentTab = _Tab.logcat;
        });
        await _fetchLogcat();
      case _PackageMenuAction.pullApks:
        await _runDeviceAction(
          () =>
              _ctrl.pullPackageApksDetailed(packageName, serial: _targetSerial),
        );
      case _PackageMenuAction.launch:
        await _runDeviceAction(
          () => _ctrl.startPackageDetailed(packageName, serial: _targetSerial),
        );
      case _PackageMenuAction.forceStop:
        await _runDeviceAction(
          () => _ctrl.forceStopAppDetailed(packageName, serial: _targetSerial),
        );
      case _PackageMenuAction.clearData:
        final confirmed = await _confirmAction(
          title: isZh ? '清除 APP 数据' : 'Clear app data',
          message: isZh
              ? '将执行 pm clear $packageName，应用数据会被清空。'
              : 'This will run pm clear $packageName and erase app data.',
          confirmLabel: isZh ? '清除' : 'Clear',
        );
        if (!confirmed) return;
        await _runDeviceAction(
          () => _ctrl.clearPackageDataDetailed(
            packageName,
            serial: _targetSerial,
          ),
        );
      case _PackageMenuAction.uninstall:
        final confirmed = await _confirmAction(
          title: isZh ? '卸载 APP' : 'Uninstall app',
          message: isZh
              ? '将从当前设备卸载 $packageName。'
              : 'This will uninstall $packageName from the current device.',
          confirmLabel: isZh ? '卸载' : 'Uninstall',
        );
        if (!confirmed) return;
        await _runDeviceAction(
          () => _ctrl.uninstallPackageDetailed(
            packageName,
            serial: _targetSerial,
          ),
        );
        await _doRefreshPackages();
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final isZh = openHandIsChineseLocale(context);
    final result = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(isZh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _showProcessMenu(
    AndroidProcess process,
    Offset? globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final center = overlay.size.center(Offset.zero);
    final position = globalPosition ?? overlay.localToGlobal(center);
    final isZh = openHandIsChineseLocale(context);
    final isPackageProcess = _looksLikePackageName(process.name);
    final selected = await showMenu<_ProcessMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _ProcessMenuAction.copyPid,
          child: Text(isZh ? '复制 PID' : 'Copy PID'),
        ),
        PopupMenuItem(
          value: _ProcessMenuAction.copyName,
          child: Text(isZh ? '复制进程名' : 'Copy process name'),
        ),
        PopupMenuItem(
          value: _ProcessMenuAction.logcatPid,
          child: Text(isZh ? '按 PID 过滤 Logcat' : 'Filter logcat by PID'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _ProcessMenuAction.kill,
          child: Text(isZh ? 'kill -9 进程...' : 'kill -9 process...'),
        ),
        if (isPackageProcess)
          PopupMenuItem(
            value: _ProcessMenuAction.forceStopPackage,
            child: Text(isZh ? '强制停止包名' : 'Force-stop package'),
          ),
      ],
    );
    if (!mounted || selected == null) return;
    await _handleProcessAction(process, selected);
  }

  Future<void> _handleProcessAction(
    AndroidProcess process,
    _ProcessMenuAction action,
  ) async {
    final isZh = openHandIsChineseLocale(context);
    switch (action) {
      case _ProcessMenuAction.copyPid:
        await _copyText('${process.pid}');
      case _ProcessMenuAction.copyName:
        await _copyText(process.name);
      case _ProcessMenuAction.logcatPid:
        setState(() {
          _logcatPidCtrl.text = '${process.pid}';
          _logcatPackageFilterEnabled = false;
          _currentTab = _Tab.logcat;
        });
        await _fetchLogcat();
      case _ProcessMenuAction.kill:
        final confirmed = await _confirmAction(
          title: isZh ? '终止进程' : 'Kill process',
          message: isZh
              ? '将执行 kill -9 ${process.pid} (${process.name})。'
              : 'This will run kill -9 ${process.pid} (${process.name}).',
          confirmLabel: 'kill -9',
        );
        if (!confirmed) return;
        await _runDeviceAction(
          () => _ctrl.killProcessDetailed(process.pid, serial: _targetSerial),
        );
        await _doRefreshProcesses();
      case _ProcessMenuAction.forceStopPackage:
        if (!_looksLikePackageName(process.name)) return;
        await _runDeviceAction(
          () => _ctrl.forceStopAppDetailed(process.name, serial: _targetSerial),
        );
        await _doRefreshProcesses();
    }
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
        config.adbMcpEnabled
            ? (isZh ? '已启用' : 'enabled')
            : (isZh ? '未启用' : 'disabled'),
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

  // ── Toolchain tab ───────────────────────────────────────────────────────

  Widget _buildToolchainTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final requiredMissing = _toolchainRows
        .where((row) => row.probe.required && !row.ok)
        .length;
    final optionalMissing = _toolchainRows
        .where((row) => !row.probe.required && !row.ok)
        .length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isZh ? 'Android 逆向工具链' : 'Android reverse toolchain',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_toolchainRows.isNotEmpty)
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      isZh
                          ? '必需缺失 $requiredMissing · 可选缺失 $optionalMissing'
                          : 'Required missing $requiredMissing · optional missing $optionalMissing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: requiredMissing == 0
                            ? cs.onSurfaceVariant
                            : cs.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              SizedBox(
                height: _kAdbInlineControlHeight,
                child: FilledButton.tonalIcon(
                  onPressed: _loadingToolchain ? null : _refreshToolchain,
                  icon: _loadingToolchain
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.refresh_rounded, size: 14),
                  label: Text(isZh ? '刷新' : 'Refresh'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingToolchain && _toolchainRows.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : OpenHandSafeScrollbar(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _toolchainRows.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (_, i) {
                      final row = _toolchainRows[i];
                      final ok = row.ok;
                      final statusColor = ok
                          ? cs.primary
                          : row.probe.required
                          ? cs.error
                          : cs.tertiary;
                      return ListTile(
                        leading: Icon(
                          ok
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                          color: statusColor,
                        ),
                        title: Row(
                          children: [
                            Text(
                              row.probe.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (row.probe.required) ...[
                              const SizedBox(width: 8),
                              Chip(
                                label: Text(isZh ? '必需' : 'required'),
                                visualDensity: VisualDensity.compact,
                                side: BorderSide.none,
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                ok ? row.displayValue : row.installHint(isZh),
                                style: TextStyle(
                                  fontFamily: ok ? 'monospace' : null,
                                  fontSize: 12,
                                  color: ok ? cs.onSurface : statusColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${isZh ? "耗时" : "Duration"}: ${row.durationMs}ms',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              tooltip: isZh ? '复制诊断' : 'Copy diagnostic',
                              onPressed: () => _copyText(
                                '${row.probe.label}\n${row.displayValue}\n${row.installHint(isZh)}',
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            PopupMenuButton<_ToolchainCommandAction>(
                              tooltip: isZh
                                  ? '复制安装/维护命令'
                                  : 'Copy setup commands',
                              icon: const Icon(
                                Icons.terminal_rounded,
                                size: 16,
                              ),
                              itemBuilder: (context) =>
                                  _toolchainCommandMenuItems(row.probe, isZh),
                              onSelected: (action) => _copyToolchainCommand(
                                row.probe,
                                action,
                                isZh,
                              ),
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

  // ── MCP / plugins tab ───────────────────────────────────────────────────

  Widget _buildMcpPluginsTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final mcpController = context.watch<McpController>();
    final pluginController = context.watch<PluginServiceController>();
    final serverRows = _androidMcpServerViews(mcpController);
    final toolSearchNames = _androidMcpToolSearchNames(serverRows);
    final toolSearchQuery = toolSearchNames.isEmpty
        ? _kAndroidMcpToolSearchFallbackQuery
        : 'select:${toolSearchNames.take(_kMcpToolSearchLimit).join(',')}';
    final runtimePlugins = _kAndroidRuntimePluginIds
        .map(pluginController.pluginById)
        .whereType<PluginInfo>()
        .toList(growable: false);
    final installedRuntimeCount = runtimePlugins
        .where((plugin) => plugin.isInstalled)
        .length;
    final totalAndroidTools = serverRows.fold<int>(
      0,
      (sum, row) => sum + row.matchedTools.length,
    );

    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isZh ? 'MCP / 插件联动' : 'MCP / plugin linkage',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                isZh
                    ? '${serverRows.length} 个相关 MCP · $totalAndroidTools 个相关工具'
                    : '${serverRows.length} related MCP · $totalAndroidTools related tools',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: _kAdbInlineControlHeight,
                child: FilledButton.tonalIcon(
                  onPressed: mcpController.isLoading
                      ? null
                      : () => unawaited(mcpController.refresh()),
                  icon: mcpController.isLoading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.sync_rounded, size: 14),
                  label: Text(isZh ? '刷新 MCP' : 'Refresh MCP'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: _kAdbInlineControlHeight,
                child: FilledButton.tonalIcon(
                  onPressed:
                      pluginController.isLoading || pluginController.isOperating
                      ? null
                      : () => unawaited(pluginController.rescan()),
                  icon: pluginController.isLoading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.refresh_rounded, size: 14),
                  label: Text(isZh ? '扫描插件' : 'Scan plugins'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoCard(
            cs: cs,
            theme: theme,
            icon: Icons.info_outline_rounded,
            text: isZh
                ? '此页只展示 OpenHand 已配置的 MCP server、工具目录和相邻运行时状态。Android 专用 MCP / Frida / IDA / anything-analyzer 仍需在全局 MCP 面板按服务自身说明安装或启用。'
                : 'This page shows configured MCP servers, discovered tools, and adjacent runtime prerequisites. Android-specific MCP, Frida, IDA, and anything-analyzer servers still need to be installed or enabled from the global MCP panel.',
          ),
          const SizedBox(height: 10),
          _monospaceCard(
            cs,
            [
              '${isZh ? "MCP 配置" : "MCP config"}: ${mcpController.serversFilePath}',
              '${isZh ? "MCP 存储" : "MCP storage"}: ${mcpController.storageDirectoryPath}',
              '${isZh ? "插件运行时" : "Plugin runtimes"}: $installedRuntimeCount/${runtimePlugins.length}',
            ].join('\n'),
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? 'ToolSearch 建议' : 'ToolSearch suggestion',
            command: toolSearchQuery,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  isZh
                      ? '生成会话级 MCP 模板、ADB 短超时包装器、动态预检脚本和 Frida runbook，供线程直接读取。'
                      : 'Generate session MCP templates, short-timeout ADB wrapper, dynamic preflight script, and Frida runbook for the thread.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: _kAdbInlineControlHeight,
                child: FilledButton.tonalIcon(
                  onPressed: _writingMcpArtifacts
                      ? null
                      : _ensureMcpLinkageArtifacts,
                  icon: _writingMcpArtifacts
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.article_rounded, size: 14),
                  label: Text(isZh ? '生成联动工件' : 'Generate artifacts'),
                ),
              ),
            ],
          ),
          if (_mcpArtifactOutput?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            _monospaceCard(cs, _mcpArtifactOutput!.trim()),
          ],
          const SizedBox(height: 18),
          _sectionTitle(
            theme,
            cs,
            isZh ? 'Android 相关 MCP' : 'Android-related MCP',
          ),
          const SizedBox(height: 8),
          if (mcpController.errorMessage?.trim().isNotEmpty ?? false) ...[
            _InfoCard(
              cs: cs,
              theme: theme,
              icon: Icons.error_outline_rounded,
              text:
                  '${isZh ? "MCP 加载异常" : "MCP load error"}: ${mcpController.errorMessage}',
            ),
            const SizedBox(height: 8),
          ],
          if (serverRows.isEmpty)
            _InfoCard(
              cs: cs,
              theme: theme,
              icon: Icons.search_off_rounded,
              text: isZh
                  ? '当前未发现名称、命令或工具描述中包含 ADB / Android / Frida / IDA / jadx / apktool / Flutter 逆向关键词的 MCP server。'
                  : 'No configured MCP server currently matches ADB / Android / Frida / IDA / jadx / apktool / Flutter reverse keywords.',
            )
          else
            for (final row in serverRows) ...[
              _buildMcpServerCard(row, cs, theme, isZh),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 14),
          _sectionTitle(
            theme,
            cs,
            isZh ? '相邻运行时前置条件' : 'Adjacent runtime prerequisites',
          ),
          const SizedBox(height: 8),
          if (pluginController.errorMessage?.trim().isNotEmpty ?? false) ...[
            _InfoCard(
              cs: cs,
              theme: theme,
              icon: Icons.error_outline_rounded,
              text:
                  '${isZh ? "插件扫描异常" : "Plugin scan error"}: ${pluginController.errorMessage}',
            ),
            const SizedBox(height: 8),
          ],
          if (runtimePlugins.isEmpty)
            _InfoCard(
              cs: cs,
              theme: theme,
              icon: Icons.hourglass_empty_rounded,
              text: pluginController.isLoading
                  ? (isZh ? '正在扫描插件运行时...' : 'Scanning plugin runtimes...')
                  : (isZh
                        ? '插件服务暂未返回 Node.js / Python / pip / Playwright 状态。'
                        : 'Plugin service has not reported Node.js / Python / pip / Playwright status.'),
            )
          else
            for (final plugin in runtimePlugins) ...[
              _buildRuntimePluginTile(plugin, cs, theme, isZh),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 14),
          _sectionTitle(
            theme,
            cs,
            isZh ? 'CLI 工具操作建议' : 'CLI tool setup actions',
          ),
          const SizedBox(height: 8),
          if (_loadingToolchain && _toolchainRows.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_toolchainRows.isEmpty)
            _InfoCard(
              cs: cs,
              theme: theme,
              icon: Icons.construction_rounded,
              text: isZh
                  ? '尚未扫描 Android 逆向工具链。点击上方刷新 MCP 或进入工具链面板刷新。'
                  : 'Android reverse toolchain has not been scanned yet. Refresh above or open the Toolchain tab.',
            )
          else
            for (final row in _toolchainRows) ...[
              _buildToolchainCommandTile(row, cs, theme, isZh),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 14),
          _sectionTitle(theme, cs, isZh ? '配置模板' : 'Config templates'),
          const SizedBox(height: 8),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? 'stdio MCP 模板（替换包名）' : 'stdio MCP template',
            command: _kAndroidStdioMcpConfigTemplate,
          ),
          const SizedBox(height: 8),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? '本地 HTTP/SSE MCP 模板' : 'Local HTTP/SSE MCP template',
            command: _kAndroidHttpMcpConfigTemplate,
          ),
          const SizedBox(height: 14),
          _InfoCard(
            cs: cs,
            theme: theme,
            icon: Icons.rule_rounded,
            text: isZh
                ? '线程内只调用工具目录真实列出的 mcp__* 名称。若这里只能看到模板而没有工具，请先在 MCP 面板补齐 server 并刷新工具目录。'
                : 'Thread tools must use real mcp__* names from the catalog. If only templates are shown here, add the server in the MCP panel and refresh its tool catalog first.',
          ),
        ],
      ),
    );
  }

  Widget _buildMcpServerCard(
    _AndroidMcpServerView row,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    final server = row.server;
    final catalog = row.catalog;
    final health = row.health;
    final healthColor = _mcpHealthColor(health.status, cs);
    final catalogColor = _mcpCatalogColor(catalog.status, cs);
    final tools = row.matchedTools.take(_kMcpToolPreviewLimit).toList();
    final queryNames = tools
        .map((tool) => _mcpResolvedToolName(server, tool))
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final query = queryNames.isEmpty ? null : 'select:${queryNames.join(',')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                server.enabled
                    ? Icons.extension_rounded
                    : Icons.extension_off_rounded,
                size: 18,
                color: server.enabled ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      server.name,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      server.summary.isEmpty
                          ? server.type.transportValue
                          : server.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: isZh ? '刷新此 MCP 工具目录' : 'Refresh this MCP catalog',
                icon: catalog.isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    : const Icon(Icons.sync_rounded, size: 16),
                onPressed: catalog.isLoading
                    ? null
                    : () => unawaited(
                        context.read<McpController>().refreshServerTools(
                          server.name,
                        ),
                      ),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
              if (query != null)
                IconButton(
                  tooltip: isZh ? '复制 ToolSearch 查询' : 'Copy ToolSearch query',
                  icon: const Icon(Icons.manage_search_rounded, size: 16),
                  onPressed: () => _copyText(query),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StatusPill(
                label: server.enabled
                    ? (isZh ? '已启用' : 'enabled')
                    : (isZh ? '未启用' : 'disabled'),
                color: server.enabled ? cs.primary : cs.outline,
              ),
              _StatusPill(
                label:
                    '${isZh ? "健康" : "health"}: ${_mcpHealthStatusLabel(health.status, isZh)}',
                color: healthColor,
              ),
              _StatusPill(
                label:
                    '${isZh ? "目录" : "catalog"}: ${_mcpCatalogStatusLabel(catalog.status, isZh)}',
                color: catalogColor,
              ),
              _StatusPill(
                label:
                    '${isZh ? "相关工具" : "related tools"}: ${row.matchedTools.length}/${catalog.tools.length}',
                color: row.matchedTools.isEmpty ? cs.outline : cs.primary,
              ),
            ],
          ),
          if (health.errorMessage?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(
              health.errorMessage!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          if (catalog.errorMessage?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(
              catalog.errorMessage!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          if (tools.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              tools
                  .map((tool) => _mcpResolvedToolName(server, tool))
                  .join('\n'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: cs.onSurface,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRuntimePluginTile(
    PluginInfo plugin,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    final color = plugin.isInstalled
        ? plugin.enabled
              ? cs.primary
              : cs.outline
        : cs.tertiary;
    final version = plugin.installedVersion?.trim();
    final path = plugin.installPath?.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.58)),
      ),
      child: Row(
        children: [
          Icon(
            plugin.isInstalled
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    plugin.id,
                    if (version != null && version.isNotEmpty) version,
                    if (plugin.hasUpdate) isZh ? '有可用更新' : 'update available',
                    if (path != null && path.isNotEmpty) path,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFamily: path == null ? null : 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(
            label: plugin.isInstalled
                ? plugin.enabled
                      ? (isZh ? '可用' : 'ready')
                      : (isZh ? '已禁用' : 'disabled')
                : (isZh ? '未安装' : 'missing'),
            color: color,
          ),
          if (path != null && path.isNotEmpty) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: isZh ? '复制路径' : 'Copy path',
              icon: const Icon(Icons.copy_rounded, size: 15),
              onPressed: () => _copyText(path),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolchainCommandTile(
    AndroidReverseToolchainProbeResult row,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    final ok = row.ok;
    final color = ok
        ? cs.primary
        : row.probe.required
        ? cs.error
        : cs.tertiary;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.58)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 17,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.probe.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusPill(
                label: ok
                    ? (isZh ? '已安装' : 'installed')
                    : row.probe.required
                    ? (isZh ? '必需缺失' : 'required missing')
                    : (isZh ? '可选缺失' : 'optional missing'),
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            ok ? row.displayValue : row.installHint(isZh),
            maxLines: 2,
            style: TextStyle(
              fontFamily: ok ? 'monospace' : null,
              fontSize: 12,
              color: ok ? cs.onSurface : color,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in _toolchainVisibleActions(row.probe))
                _SmallActionButton(
                  icon: _toolchainCommandIcon(action),
                  label: _toolchainCommandLabel(action, isZh),
                  onPressed: () =>
                      _copyToolchainCommand(row.probe, action, isZh),
                ),
            ],
          ),
        ],
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
                      final selected = _selectedPackageName == pkg;
                      return GestureDetector(
                        onSecondaryTapDown: (details) =>
                            _showPackageMenu(pkg, details.globalPosition),
                        onDoubleTap: () => _showPackageMenu(pkg, null),
                        child: ListTile(
                          selected: selected,
                          selectedTileColor: cs.primaryContainer.withValues(
                            alpha: 0.22,
                          ),
                          leading: Icon(
                            Icons.apps_rounded,
                            size: 18,
                            color: selected ? cs.primary : cs.onSurfaceVariant,
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
                              const SizedBox(width: _kIconButtonGap),
                              IconButton(
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 15,
                                ),
                                tooltip: isZh ? '启动 APP' : 'Launch app',
                                onPressed: _runningDeviceAction
                                    ? null
                                    : () => _runDeviceAction(
                                        () => _ctrl.startPackageDetailed(
                                          pkg,
                                          serial: _targetSerial,
                                        ),
                                      ),
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: _kIconButtonGap),
                              IconButton(
                                icon: const Icon(
                                  Icons.stop_rounded,
                                  size: 14,
                                  color: Colors.redAccent,
                                ),
                                tooltip: isZh ? '强制停止' : 'Force stop',
                                onPressed: _runningDeviceAction
                                    ? null
                                    : () async {
                                        await _runDeviceAction(
                                          () => _ctrl.forceStopAppDetailed(
                                            pkg,
                                            serial: _targetSerial,
                                          ),
                                        );
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              isZh
                                                  ? '已发送强制停止：$pkg'
                                                  : 'Force-stop sent: $pkg',
                                            ),
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                          ),
                                        );
                                      },
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: _kIconButtonGap),
                              IconButton(
                                icon: const Icon(
                                  Icons.more_horiz_rounded,
                                  size: 16,
                                ),
                                tooltip: isZh ? '更多操作' : 'More actions',
                                onPressed: () => _showPackageMenu(pkg, null),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          onTap: () => _analyzePackage(pkg),
                          dense: true,
                        ),
                      );
                    },
                  ),
                ),
        ),
        if (_selectedPackageName != null) ...[
          Divider(height: 1, color: cs.outlineVariant),
          SizedBox(
            height: 190,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${isZh ? "APP 分析" : "APP analysis"}: $_selectedPackageName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (_loadingPackageAnalysis)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      if (_capturingPackageReport)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        tooltip: isZh ? '重新分析' : 'Analyze again',
                        onPressed: _loadingPackageAnalysis
                            ? null
                            : () => _analyzePackage(_selectedPackageName!),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.snippet_folder_rounded,
                          size: 16,
                        ),
                        tooltip: isZh ? '生成 APP 信息报告' : 'Generate app report',
                        onPressed: _capturingPackageReport
                            ? null
                            : () =>
                                  _capturePackageReport(_selectedPackageName!),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        tooltip: isZh ? '复制分析结果' : 'Copy analysis',
                        onPressed: (_packageAnalysisOutput ?? '').trim().isEmpty
                            ? null
                            : () => _copyText(_packageAnalysisOutput!),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: OpenHandSafeScrollbar(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(8),
                          child: SelectableText(
                            _packageAnalysisOutput ??
                                (isZh
                                    ? '正在读取 APP 信息...'
                                    : 'Reading app info...'),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.45,
                              color: cs.onSurface,
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
        ],
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
                child: SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: TextField(
                    controller: _processFilter,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isZh ? '过滤进程名...' : 'Filter process name...',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _doRefreshProcesses(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: _kAdbInlineControlHeight,
                child: FilledButton.tonalIcon(
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
                      return GestureDetector(
                        onSecondaryTapDown: (details) =>
                            _showProcessMenu(p, details.globalPosition),
                        onDoubleTap: () => _showProcessMenu(p, null),
                        child: ListTile(
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                onPressed: () => _copyText('${p.pid}'),
                                tooltip: isZh ? '复制 PID' : 'Copy PID',
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: _kIconButtonGap),
                              IconButton(
                                icon: const Icon(
                                  Icons.more_horiz_rounded,
                                  size: 16,
                                ),
                                onPressed: () => _showProcessMenu(p, null),
                                tooltip: isZh ? '更多操作' : 'More actions',
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          dense: true,
                        ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Logcat (${_logcatLines.length} lines)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_loadingLogcat)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    ),
                  const Spacer(),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          SizedBox(
                            height: _kAdbInlineControlHeight,
                            child: FilledButton.tonalIcon(
                              onPressed: _loadingLogcat ? null : _fetchLogcat,
                              icon: const Icon(Icons.refresh_rounded, size: 14),
                              label: Text(isZh ? '刷新' : 'Refresh'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: _kAdbInlineControlHeight,
                            child: FilledButton.tonalIcon(
                              onPressed: _capturingLogcatSnapshot
                                  ? null
                                  : _captureLogcatArtifactSnapshot,
                              icon: _capturingLogcatSnapshot
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.6,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.snippet_folder_rounded,
                                      size: 14,
                                    ),
                              label: Text(isZh ? '快照' : 'Snapshot'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: _kAdbInlineControlHeight,
                            child: FilledButton.tonalIcon(
                              onPressed: _logcatLines.isEmpty
                                  ? null
                                  : _saveLogcatSnapshot,
                              icon: const Icon(
                                Icons.save_alt_rounded,
                                size: 14,
                              ),
                              label: Text(isZh ? '保存' : 'Save'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: _kAdbInlineControlHeight,
                            child: FilledButton.tonalIcon(
                              onPressed: _logcatLines.isEmpty
                                  ? null
                                  : () => _copyText(_logcatLines.join('\n')),
                              icon: const Icon(Icons.copy_rounded, size: 14),
                              label: Text(isZh ? '复制' : 'Copy'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: _kAdbInlineControlHeight,
                            child: FilledButton.tonalIcon(
                              onPressed: _loadingLogcat ? null : _clearLogcat,
                              icon: const Icon(
                                Icons.delete_sweep_rounded,
                                size: 14,
                              ),
                              label: Text(isZh ? '清空' : 'Clear'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    height: _kAdbInlineControlHeight,
                    child: TextField(
                      controller: _logcatFilterCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: isZh ? 'Tag 过滤' : 'Tag filter',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        suffixIcon: _logcatFilterCtrl.text.trim().isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                tooltip: isZh ? '清空过滤' : 'Clear filter',
                                onPressed: () {
                                  setState(() => _logcatFilterCtrl.clear());
                                  _fetchLogcat();
                                },
                              ),
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _fetchLogcat(),
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    height: _kAdbInlineControlHeight,
                    child: DropdownButtonFormField<String>(
                      initialValue: _logcatLevel,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: isZh ? '等级' : 'Level',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        for (final level in _kLogcatLevels)
                          DropdownMenuItem<String>(
                            value: level,
                            child: Text(level),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _logcatLevel = value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    height: _kAdbInlineControlHeight,
                    child: TextField(
                      controller: _logcatPidCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'PID',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        suffixIcon: _logcatPidCtrl.text.trim().isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                tooltip: isZh ? '清空 PID' : 'Clear PID',
                                onPressed: () {
                                  setState(() => _logcatPidCtrl.clear());
                                  _fetchLogcat();
                                },
                              ),
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _fetchLogcat(),
                    ),
                  ),
                  FilterChip(
                    selected: _logcatPackageFilterEnabled,
                    avatar: const Icon(Icons.apps_rounded, size: 15),
                    label: Text(
                      _logcatPackageTarget() ?? (isZh ? '未指定包名' : 'No package'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onSelected: _logcatPackageTarget() == null
                        ? null
                        : (value) {
                            setState(() {
                              _logcatPackageFilterEnabled = value;
                              if (value) _logcatPidCtrl.clear();
                            });
                          },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (_logcatError != null && _logcatLines.isNotEmpty) ...[
                const SizedBox(height: 8),
                _InfoCard(
                  cs: cs,
                  theme: theme,
                  icon: Icons.info_outline_rounded,
                  text: _logcatError!,
                ),
              ],
              if (_logcatArtifactOutput?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                _monospaceCard(cs, _logcatArtifactOutput!.trim()),
              ],
            ],
          ),
        ),
        Expanded(
          child: _logcatLines.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 32,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _logcatError ??
                            (isZh
                                ? '尚未加载 Logcat'
                                : 'Logcat has not been loaded yet'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: _loadingLogcat ? null : _fetchLogcat,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: Text(isZh ? '加载 Logcat' : 'Load logcat'),
                      ),
                    ],
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final snippets = _buildFridaSnippetPane(cs, theme, isZh);
          final editor = _buildFridaEditorPane(cs, theme, isZh);
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFridaHeader(cs, theme, isZh),
                const SizedBox(height: 10),
                SizedBox(height: 150, child: snippets),
                const SizedBox(height: 10),
                Expanded(child: editor),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFridaHeader(cs, theme, isZh),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 286, child: snippets),
                    const SizedBox(width: 12),
                    Expanded(child: editor),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFridaHeader(ColorScheme cs, ThemeData theme, bool isZh) {
    return _InfoCard(
      cs: cs,
      theme: theme,
      icon: Icons.bug_report_rounded,
      text: isZh
          ? '先从内置 snippet 加载脚本，再按当前包名生成 spawn / attach 命令。实际注入仍由 AI 代理通过 Frida MCP 或 Bash 执行。'
          : 'Load a built-in snippet first, then use generated spawn/attach commands for the current package. Injection is still executed by the AI agent via Frida MCP or Bash.',
    );
  }

  Widget _buildFridaSnippetPane(ColorScheme cs, ThemeData theme, bool isZh) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: OpenHandSafeScrollbar(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: _kFridaSnippetPresets.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: cs.outlineVariant),
          itemBuilder: (context, index) {
            final preset = _kFridaSnippetPresets[index];
            final selected = _selectedFridaSnippetAsset == preset.assetPath;
            return ListTile(
              selected: selected,
              selectedTileColor: cs.primaryContainer.withValues(alpha: 0.28),
              leading: Icon(
                selected ? Icons.check_circle_rounded : Icons.code_rounded,
                size: 17,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              title: Text(
                preset.label(isZh),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                preset.desc(isZh),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.download_rounded, size: 15),
                tooltip: isZh ? '加载' : 'Load',
                onPressed: () => _loadFridaSnippet(preset),
                visualDensity: VisualDensity.compact,
              ),
              dense: true,
              onTap: () => _loadFridaSnippet(preset),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFridaEditorPane(ColorScheme cs, ThemeData theme, bool isZh) {
    final scriptAsset = _selectedFridaSnippetAsset;
    final scriptArg = scriptAsset == null
        ? '<script.js>'
        : _commandToken(scriptAsset);
    final pkg = _commandToken(_packageCommandTarget());
    const savedScriptArg = '<saved-script.js>';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TextField(
            controller: _fridaScriptCtrl,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              hintText: isZh
                  ? '// 选择 snippet 或粘贴脚本...'
                  : '// Load a snippet or paste script...',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                scriptAsset ??
                    (isZh ? '未选择内置 snippet' : 'No built-in snippet selected'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontFamily: scriptAsset == null ? null : 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed:
                  _fridaScriptCtrl.text.trim().isEmpty || _savingFridaScript
                  ? null
                  : _saveFridaScriptArtifact,
              icon: _savingFridaScript
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  : const Icon(Icons.save_alt_rounded, size: 14),
              label: Text(isZh ? '保存工件' : 'Save artifact'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _fridaScriptCtrl.text.trim().isEmpty
                  ? null
                  : () => _copyText(_fridaScriptCtrl.text),
              icon: const Icon(Icons.copy_rounded, size: 14),
              label: Text(isZh ? '复制脚本' : 'Copy script'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: OpenHandSafeScrollbar(
            child: ListView(
              children: [
                if (_fridaArtifactOutput?.trim().isNotEmpty ?? false) ...[
                  _monospaceCard(cs, _fridaArtifactOutput!.trim()),
                  const SizedBox(height: 8),
                ],
                _commandCard(
                  cs,
                  theme,
                  isZh,
                  title: isZh ? '读取脚本工件' : 'Read script artifacts',
                  command:
                      'find ${_shellQuote(_ctrl.fridaScriptsDir)} -maxdepth 1 -type f | sort\n'
                      'cat ${_shellQuote(_ctrl.fridaScriptsDir)}/<saved-script>.js',
                ),
                const SizedBox(height: 8),
                _commandCard(
                  cs,
                  theme,
                  isZh,
                  title: isZh ? '设备端 Frida 准备' : 'Prepare device Frida',
                  command:
                      'frida --version\n'
                      '${_adbCommandPrefix()} shell getprop ro.product.cpu.abi\n'
                      '${_adbCommandPrefix()} shell pidof frida-server || true\n'
                      '${_adbCommandPrefix()} shell ls -l /data/local/tmp/frida-server\n'
                      '# ${isZh ? "按 ABI 下载匹配版本后再推送；执行前需用户确认" : "Download the matching server for the ABI before pushing; ask for approval before running"}\n'
                      '# arm64-v8a=android-arm64, armeabi-v7a=android-arm, x86_64=android-x86_64\n'
                      'FRIDA_VERSION="\$(frida --version)"\n'
                      'curl -L -o /tmp/frida-server.xz "https://github.com/frida/frida/releases/download/\$FRIDA_VERSION/frida-server-\$FRIDA_VERSION-android-arm64.xz"\n'
                      'xz -dkf /tmp/frida-server.xz\n'
                      '${_adbCommandPrefix()} push /tmp/frida-server /data/local/tmp/frida-server\n'
                      '${_adbCommandPrefix()} shell "chmod 755 /data/local/tmp/frida-server; /data/local/tmp/frida-server >/dev/null 2>&1 &"\n'
                      '${_adbCommandPrefix()} forward tcp:27042 tcp:27042\n'
                      'frida-ps -U',
                ),
                const SizedBox(height: 8),
                _commandCard(
                  cs,
                  theme,
                  isZh,
                  title: isZh ? 'Spawn 注入' : 'Spawn inject',
                  command:
                      'frida -U -f $pkg -l $scriptArg --no-pause\n'
                      'frida -U -f $pkg -l $savedScriptArg --no-pause',
                ),
                const SizedBox(height: 8),
                _commandCard(
                  cs,
                  theme,
                  isZh,
                  title: isZh ? 'Attach / 诊断' : 'Attach / diagnose',
                  command:
                      'frida-ps -Uai | grep $pkg\n'
                      'frida -U -n $pkg -l $scriptArg\n'
                      '${_adbCommandPrefix()} forward tcp:27042 tcp:27042',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Network tab ─────────────────────────────────────────────────────────

  Widget _buildNetworkTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final networkDir = _ctrl.networkDir;
    final addonPath = _ctrl.mitmproxyAddonPath;
    final addonOutput = _networkAddonOutput?.trim();
    final adb = _adbCommandPrefix();
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 220),
                child: Text(
                  isZh ? '网络抓包 (mitmproxy)' : 'Network capture (mitmproxy)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                height: _kAdbInlineControlHeight,
                child: FilledButton.tonalIcon(
                  onPressed: _writingNetworkAddon
                      ? null
                      : _ensureMitmproxyAddon,
                  icon: _writingNetworkAddon
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.8),
                        )
                      : const Icon(Icons.receipt_long_rounded, size: 15),
                  label: Text(isZh ? '生成 JSONL Addon' : 'Generate JSONL addon'),
                ),
              ),
              if (addonOutput != null && addonOutput.isNotEmpty)
                SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _copyText(addonOutput),
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: Text(isZh ? '复制结果' : 'Copy result'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _InfoCard(
            cs: cs,
            theme: theme,
            icon: Icons.info_outline_rounded,
            text: isZh
                ? '网络流量由 mitmproxy 代理拦截。可先生成 JSONL addon，把 HTTP 记录写入 network.jsonl；HTTPS 需先在"证书"面板安装 CA 证书。'
                : 'Traffic is intercepted by mitmproxy. Generate the JSONL addon to write HTTP records into network.jsonl; HTTPS requires installing the CA cert in the Certs tab first.',
          ),
          if (addonOutput != null && addonOutput.isNotEmpty) ...[
            const SizedBox(height: 10),
            _monospaceCard(cs, addonOutput),
          ],
          const SizedBox(height: 12),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? '启动抓包' : 'Start capture',
            command:
                'mkdir -p ${_shellQuote(networkDir)}\n'
                'OPENHAND_NETWORK_JSONL=${_shellQuote(_ctrl.networkJsonlPath)} mitmdump -p 8080 -s ${_shellQuote(addonPath)} -w ${_shellQuote('$networkDir/flows.mitm')}',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? '设备代理' : 'Device proxy',
            command:
                '$adb shell settings put global http_proxy <host-ip>:8080\n'
                '$adb shell settings get global http_proxy\n'
                '$adb shell settings delete global http_proxy',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? '读取抓包文件' : 'Read saved flows',
            command:
                'mitmproxy -r ${_shellQuote('$networkDir/flows.mitm')}\n'
                '# ${isZh ? "建议同时保存结构化摘要" : "Recommended structured summary"}\n'
                'mitmdump -nr ${_shellQuote('$networkDir/flows.mitm')} > ${_shellQuote('$networkDir/flows.txt')}',
          ),
          const SizedBox(height: 10),
          _InfoCard(
            cs: cs,
            theme: theme,
            icon: Icons.folder_rounded,
            text:
                '${isZh ? "本地工件目录" : "Local artifacts"}: $networkDir\n'
                'network.jsonl\n'
                'openhand_mitm_jsonl.py',
          ),
        ],
      ),
    );
  }

  // ── Static analysis tab ─────────────────────────────────────────────────

  Widget _buildStaticTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final apk = _apkCommandTarget();
    final packageSlug = _staticArtifactSlug();
    final decompiledDir = '${_ctrl.decompiledDir}/$packageSlug';
    final scanOutput = _staticQuickScanOutput?.trim();
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 220),
                child: Text(
                  isZh ? '静态分析工作台' : 'Static analysis workbench',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                height: _kAdbInlineControlHeight,
                child: FilledButton.tonalIcon(
                  onPressed: _runningStaticQuickScan
                      ? null
                      : _runStaticQuickScan,
                  icon: _runningStaticQuickScan
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.8),
                        )
                      : const Icon(Icons.manage_search_rounded, size: 15),
                  label: Text(isZh ? '快速扫描 APK' : 'Quick scan APK'),
                ),
              ),
              if (scanOutput != null && scanOutput.isNotEmpty) ...[
                SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _copyText(scanOutput),
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: Text(isZh ? '复制结果' : 'Copy result'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _InfoCard(
            cs: cs,
            theme: theme,
            icon: Icons.folder_rounded,
            text: isZh
                ? '快速扫描会读取当前 APK，生成 badging、Manifest/组件、签名证书、嵌套 APK、Flutter/native/可疑文件、业务网络候选、URL/域名/IP、网络字符串来源到 $decompiledDir/quick_scan。'
                : 'Quick scan reads the current APK and writes badging, Manifest/components, signing certs, nested APKs, Flutter/native/suspicious files, business network candidates, URL/domain/IP, and network string sources to $decompiledDir/quick_scan.',
          ),
          if (scanOutput != null && scanOutput.isNotEmpty) ...[
            const SizedBox(height: 10),
            _monospaceCard(cs, scanOutput),
          ],
          const SizedBox(height: 12),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? '读取快速扫描产物' : 'Read quick scan artifacts',
            command:
                'cd ${_shellQuote('$decompiledDir/quick_scan')}\n'
                'cat network_candidates.txt business_urls.txt business_domains.txt business_network_sources.txt\n'
                'cat network_sources.txt urls.txt domains.txt ips.txt\n'
                'cat flutter.txt native_libs.txt suspicious_files.txt nested_apks.txt',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? 'APK 身份与签名' : 'APK identity and signing',
            command:
                'aapt dump badging $apk | head -40\n'
                'apksigner verify --print-certs $apk',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? 'jadx 反编译' : 'jadx decompile',
            command:
                'mkdir -p ${_shellQuote('$decompiledDir/jadx')}\n'
                'jadx -d ${_shellQuote('$decompiledDir/jadx')} $apk\n'
                'grep -RInE "sign|encrypt|token|https?://" ${_shellQuote('$decompiledDir/jadx')} | head -200',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? 'apktool 解包 + smali' : 'apktool unpack + smali',
            command:
                'apktool d -f $apk -o ${_shellQuote('$decompiledDir/apktool')}\n'
                'grep -RInE "invoke-.*(sign|encrypt)|https?://" ${_shellQuote('$decompiledDir/apktool/smali')} | head -200',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? '字符串快速定位' : 'Fast string scan',
            command:
                'unzip -p $apk "classes*.dex" | strings | grep -Ei "https?://|sign|encrypt|token" | head -200\n'
                'unzip -l $apk | grep -E "\\.so\$|assets/"',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? 'Flutter / Native' : 'Flutter / Native',
            command:
                'blutter libapp.so ${_shellQuote('$decompiledDir/blutter')}\n'
                'readelf -Ws lib/arm64-v8a/libxxx.so | grep -Ei "sign|encrypt|ssl|http"\n'
                'r2 -A lib/arm64-v8a/libxxx.so',
          ),
        ],
      ),
    );
  }

  // ── Certs tab ────────────────────────────────────────────────────────────

  Widget _buildCertsTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final adb = _adbCommandPrefix();
    final apk = _apkCommandTarget();
    final pkg = _packageCommandTarget();
    final artifactOutput = _certificateArtifactOutput?.trim();
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 260),
                child: Text(
                  isZh
                      ? '证书管理与 SSL Pinning'
                      : 'Certificate management & SSL Pinning',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                height: _kAdbInlineControlHeight,
                child: FilledButton.tonalIcon(
                  onPressed: _writingCertificateArtifacts
                      ? null
                      : _ensureCertificateArtifacts,
                  icon: _writingCertificateArtifacts
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.8),
                        )
                      : const Icon(Icons.description_rounded, size: 15),
                  label: Text(isZh ? '生成证书工件' : 'Generate cert artifacts'),
                ),
              ),
              if (artifactOutput != null && artifactOutput.isNotEmpty)
                SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _copyText(artifactOutput),
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: Text(isZh ? '复制结果' : 'Copy result'),
                  ),
                ),
            ],
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
          if (artifactOutput != null && artifactOutput.isNotEmpty) ...[
            const SizedBox(height: 10),
            _monospaceCard(cs, artifactOutput),
          ],
          const SizedBox(height: 12),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh
                ? 'Network Security Config 工件'
                : 'Network Security Config artifacts',
            command:
                'cat ${_shellQuote('${_ctrl.certsDir}/res/xml/network_security_config.xml')}\n'
                'cat ${_shellQuote('${_ctrl.certsDir}/AndroidManifest.application.xml')}\n'
                'bash ${_shellQuote('${_ctrl.certsDir}/install_mitm_ca_root.sh')}',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? 'APK 重签名工件' : 'APK resigning artifacts',
            command:
                'bash ${_shellQuote('${_ctrl.certsDir}/generate_debug_keystore.sh')}\n'
                'bash ${_shellQuote('${_ctrl.certsDir}/sign_repacked_apk.sh')} <unsigned.apk> <signed.apk>\n'
                'bash ${_shellQuote('${_ctrl.certsDir}/verify_apk_signature.sh')} <signed.apk>',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? '准备 mitmproxy CA' : 'Prepare mitmproxy CA',
            command:
                'CERT=~/.mitmproxy/mitmproxy-ca-cert.pem\n'
                'HASH=\$(openssl x509 -inform PEM -subject_hash_old -in "\$CERT" | head -1)\n'
                'cp "\$CERT" "\$HASH.0"\n'
                'openssl x509 -inform PEM -in "\$CERT" -noout -subject -issuer -dates',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? '推送系统 CA（需 root）' : 'Push system CA (root required)',
            command:
                '$adb root\n'
                '$adb remount\n'
                '$adb push "\$HASH.0" /system/etc/security/cacerts/\n'
                '$adb shell chmod 644 /system/etc/security/cacerts/"\$HASH.0"\n'
                '$adb shell ls -l /system/etc/security/cacerts/"\$HASH.0"',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? '检查 APK 签名证书' : 'Inspect APK signing cert',
            command: 'apksigner verify --print-certs $apk',
          ),
          const SizedBox(height: 10),
          _commandCard(
            cs,
            theme,
            isZh,
            title: isZh ? 'SSL Pinning 绕过' : 'SSL Pinning bypass',
            command:
                '# 使用 assets/prompts/android_reverse_expert/snippets/hook_ssl_pinning.js\n'
                'frida -U -f $pkg -l assets/prompts/android_reverse_expert/snippets/hook_ssl_pinning.js',
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

  Widget _sectionTitle(ThemeData theme, ColorScheme cs, String label) {
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  List<_AndroidMcpServerView> _androidMcpServerViews(McpController controller) {
    final rows = <_AndroidMcpServerView>[];
    for (final server in controller.servers) {
      final catalog = controller.toolCatalogFor(server.name);
      final health = controller.healthStatusFor(server.name);
      final matchedTools = catalog.tools
          .where(_isAndroidRelevantMcpTool)
          .toList(growable: false);
      final serverIsRelevant = _containsAndroidMcpKeyword(
        '${server.name} ${server.summary} ${server.type.transportValue}',
      );
      if (!serverIsRelevant && matchedTools.isEmpty) continue;
      rows.add(
        _AndroidMcpServerView(
          server: server,
          catalog: catalog,
          health: health,
          matchedTools: matchedTools,
        ),
      );
    }
    rows.sort((a, b) {
      final enabled = (b.server.enabled ? 1 : 0).compareTo(
        a.server.enabled ? 1 : 0,
      );
      if (enabled != 0) return enabled;
      final tools = b.matchedTools.length.compareTo(a.matchedTools.length);
      if (tools != 0) return tools;
      return a.server.name.toLowerCase().compareTo(b.server.name.toLowerCase());
    });
    return List<_AndroidMcpServerView>.unmodifiable(rows);
  }

  List<String> _androidMcpToolSearchNames(List<_AndroidMcpServerView> rows) {
    final names = <String>{};
    for (final row in rows) {
      for (final tool in row.matchedTools) {
        names.add(_mcpResolvedToolName(row.server, tool));
        if (names.length >= _kMcpToolSearchLimit) {
          return List<String>.unmodifiable(names);
        }
      }
    }
    return List<String>.unmodifiable(names);
  }

  bool _isAndroidRelevantMcpTool(McpTool tool) {
    return _containsAndroidMcpKeyword(
      '${tool.id} ${tool.name} ${tool.description}',
    );
  }

  bool _containsAndroidMcpKeyword(String raw) {
    final text = raw.toLowerCase();
    return _kAndroidMcpKeywords.any(text.contains);
  }

  List<PopupMenuEntry<_ToolchainCommandAction>> _toolchainCommandMenuItems(
    AndroidReverseToolchainProbe probe,
    bool isZh,
  ) {
    return _toolchainVisibleActions(probe)
        .map(
          (action) => PopupMenuItem<_ToolchainCommandAction>(
            value: action,
            child: Row(
              children: [
                Icon(_toolchainCommandIcon(action), size: 16),
                const SizedBox(width: 8),
                Text(_toolchainCommandLabel(action, isZh)),
              ],
            ),
          ),
        )
        .toList(growable: false);
  }

  List<_ToolchainCommandAction> _toolchainVisibleActions(
    AndroidReverseToolchainProbe probe,
  ) {
    return <_ToolchainCommandAction>[
      _ToolchainCommandAction.install,
      if (probe.updateCommand?.trim().isNotEmpty ?? false)
        _ToolchainCommandAction.update,
      if (probe.uninstallCommand?.trim().isNotEmpty ?? false)
        _ToolchainCommandAction.uninstall,
      if (probe.referenceUrl?.trim().isNotEmpty ?? false)
        _ToolchainCommandAction.reference,
    ];
  }

  Future<void> _copyToolchainCommand(
    AndroidReverseToolchainProbe probe,
    _ToolchainCommandAction action,
    bool isZh,
  ) async {
    final text = _toolchainCommandText(probe, action, isZh);
    if (text.trim().isEmpty) return;
    await _copyText(text);
  }

  String _toolchainCommandText(
    AndroidReverseToolchainProbe probe,
    _ToolchainCommandAction action,
    bool isZh,
  ) {
    return switch (action) {
      _ToolchainCommandAction.install =>
        probe.installCommand?.trim().isNotEmpty == true
            ? probe.installCommand!.trim()
            : (isZh ? probe.installHintZh : probe.installHintEn).trim(),
      _ToolchainCommandAction.update =>
        probe.updateCommand?.trim().isNotEmpty == true
            ? probe.updateCommand!.trim()
            : '',
      _ToolchainCommandAction.uninstall =>
        probe.uninstallCommand?.trim().isNotEmpty == true
            ? probe.uninstallCommand!.trim()
            : '',
      _ToolchainCommandAction.reference =>
        probe.referenceUrl?.trim().isNotEmpty == true
            ? probe.referenceUrl!.trim()
            : (isZh ? probe.installHintZh : probe.installHintEn),
    };
  }

  IconData _toolchainCommandIcon(_ToolchainCommandAction action) {
    return switch (action) {
      _ToolchainCommandAction.install => Icons.download_rounded,
      _ToolchainCommandAction.update => Icons.upgrade_rounded,
      _ToolchainCommandAction.uninstall => Icons.delete_outline_rounded,
      _ToolchainCommandAction.reference => Icons.open_in_new_rounded,
    };
  }

  String _toolchainCommandLabel(_ToolchainCommandAction action, bool isZh) {
    return switch (action) {
      _ToolchainCommandAction.install => isZh ? '复制安装' : 'Copy install',
      _ToolchainCommandAction.update => isZh ? '复制更新' : 'Copy update',
      _ToolchainCommandAction.uninstall => isZh ? '复制卸载' : 'Copy uninstall',
      _ToolchainCommandAction.reference => isZh ? '复制文档' : 'Copy docs',
    };
  }

  String _mcpResolvedToolName(McpServer server, McpTool tool) {
    final normalizedPrefix = _normalizeMcpToolToken('mcp__${server.name}');
    final normalizedToken = _normalizeMcpToolToken(tool.id);
    var candidate = '${normalizedPrefix}__$normalizedToken';
    if (candidate.length <= _kMcpRuntimeToolNameLimit) return candidate;
    final hash = _stableMcpToolNameHash(tool.id);
    final allowedTokenLength =
        _kMcpRuntimeToolNameLimit - normalizedPrefix.length - hash.length - 4;
    final preferredLength =
        allowedTokenLength > 8 && allowedTokenLength < normalizedToken.length
        ? allowedTokenLength
        : (normalizedToken.length < 24 ? normalizedToken.length : 24);
    final shortenedToken = normalizedToken.substring(0, preferredLength);
    candidate = '${normalizedPrefix}__${shortenedToken}_$hash';
    return candidate.length > _kMcpRuntimeToolNameLimit
        ? candidate.substring(0, _kMcpRuntimeToolNameLimit)
        : candidate;
  }

  String _normalizeMcpToolToken(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? 'tool' : sanitized;
  }

  String _stableMcpToolNameHash(String value) {
    var hash = 0x811c9dc5;
    for (final code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _mcpCatalogStatusLabel(McpToolCatalogStatus status, bool isZh) {
    return switch (status) {
      McpToolCatalogStatus.idle => isZh ? '未扫描' : 'idle',
      McpToolCatalogStatus.loading => isZh ? '扫描中' : 'loading',
      McpToolCatalogStatus.ready => isZh ? '已就绪' : 'ready',
      McpToolCatalogStatus.failed => isZh ? '失败' : 'failed',
    };
  }

  String _mcpHealthStatusLabel(McpServerHealthStatus status, bool isZh) {
    return switch (status) {
      McpServerHealthStatus.idle => isZh ? '未探测' : 'idle',
      McpServerHealthStatus.checking => isZh ? '探测中' : 'checking',
      McpServerHealthStatus.healthy => isZh ? '正常' : 'healthy',
      McpServerHealthStatus.unhealthy => isZh ? '异常' : 'unhealthy',
    };
  }

  Color _mcpCatalogColor(McpToolCatalogStatus status, ColorScheme cs) {
    return switch (status) {
      McpToolCatalogStatus.ready => cs.primary,
      McpToolCatalogStatus.loading => cs.tertiary,
      McpToolCatalogStatus.failed => cs.error,
      McpToolCatalogStatus.idle => cs.outline,
    };
  }

  Color _mcpHealthColor(McpServerHealthStatus status, ColorScheme cs) {
    return switch (status) {
      McpServerHealthStatus.healthy => cs.primary,
      McpServerHealthStatus.checking => cs.tertiary,
      McpServerHealthStatus.unhealthy => cs.error,
      McpServerHealthStatus.idle => cs.outline,
    };
  }

  Widget _commandCard(
    ColorScheme cs,
    ThemeData theme,
    bool isZh, {
    required String title,
    required String command,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 15),
                tooltip: isZh ? '复制命令' : 'Copy command',
                onPressed: () => _copyText(command),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
              ),
            ],
          ),
          SelectableText(
            command,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: cs.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _buildPathActionRow({
    required TextEditingController primaryController,
    required String primaryHint,
    TextEditingController? secondaryController,
    String? secondaryHint,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _pathTextField(
            controller: primaryController,
            hintText: primaryHint,
          ),
        ),
        if (secondaryController != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _pathTextField(
              controller: secondaryController,
              hintText: secondaryHint ?? '',
            ),
          ),
        ],
        const SizedBox(width: 8),
        SizedBox(
          height: _kAdbInlineControlHeight,
          child: FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
          ),
        ),
      ],
    );
  }

  Widget _pathTextField({
    required TextEditingController controller,
    required String hintText,
  }) {
    return SizedBox(
      height: _kAdbInlineControlHeight,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  String _adbCommandPrefix() {
    final serial = _targetSerial?.trim();
    if (serial == null || serial.isEmpty) return 'adb';
    return 'adb -s ${_shellQuote(serial)}';
  }

  String _normalizeAdbShellInput(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    final adbShellPrefix = RegExp(
      r"""^adb(?:\s+-s\s+(?:"[^"]+"|'[^']+'|\S+))?\s+shell\s+""",
      caseSensitive: false,
    );
    final match = adbShellPrefix.firstMatch(value);
    if (match == null) return value;
    return value.substring(match.end).trim();
  }

  String? _logcatPackageTarget() {
    final selected = _selectedPackageName?.trim();
    if (selected != null && selected.isNotEmpty) return selected;
    final configured = _ctrl.config.packageName?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return null;
  }

  String _packageCommandTarget() {
    final selected = _selectedPackageName?.trim();
    if (selected != null && selected.isNotEmpty) return selected;
    final configured = _ctrl.config.packageName?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return '<pkg>';
  }

  String _apkCommandTarget() {
    final apkPath = _ctrl.config.apkPath?.trim();
    if (apkPath == null || apkPath.isEmpty) return '<app.apk>';
    return _shellQuote(apkPath);
  }

  String _staticArtifactSlug() {
    final pkg = _logcatPackageTarget();
    if (pkg != null && pkg.isNotEmpty) return _safeArtifactName(pkg);
    final apkPath = _ctrl.config.apkPath?.trim();
    if (apkPath != null && apkPath.isNotEmpty) {
      final name = apkPath.split('/').last.trim();
      final base = name.toLowerCase().endsWith('.apk')
          ? name.substring(0, name.length - 4)
          : name;
      return _safeArtifactName(base);
    }
    return 'app';
  }

  String _safeArtifactName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty || cleaned == 'pkg' ? 'app' : cleaned;
  }

  String _shellQuote(String value) {
    if (RegExp(r'^[A-Za-z0-9_./:@%+=,-]+$').hasMatch(value)) {
      return value;
    }
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  String _commandToken(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('<') && trimmed.endsWith('>')) return trimmed;
    return _shellQuote(trimmed);
  }

  bool _looksLikePackageName(String value) {
    final packageName = value.trim();
    if (packageName.length > 220) return false;
    return RegExp(
      r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
    ).hasMatch(packageName);
  }
}

class _AndroidMcpServerView {
  const _AndroidMcpServerView({
    required this.server,
    required this.catalog,
    required this.health,
    required this.matchedTools,
  });

  final McpServer server;
  final McpToolCatalog catalog;
  final McpServerHealth health;
  final List<McpTool> matchedTools;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DeviceInfoRow extends StatelessWidget {
  const _DeviceInfoRow({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  final String label;
  final String value;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              maxLines: label.length > 12 ? 2 : 3,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: colorScheme.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForwardRow extends StatelessWidget {
  const _ForwardRow({
    required this.row,
    required this.colorScheme,
    required this.onRemove,
  });

  final String row;
  final ColorScheme colorScheme;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              row,
              maxLines: 2,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 14),
            tooltip: openHandLocalizedText(
              context,
              zh: '移除转发',
              en: 'Remove forward',
            ),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          ),
        ],
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
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
