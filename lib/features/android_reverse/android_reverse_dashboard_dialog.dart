import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/animated_menu.dart';
import '../../shared/ui/ansi_text.dart';
import '../../shared/ui/openhand_safe_scrollbar.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/structured_text_format.dart';
import '../../shared/util/timer_safety.dart';
import '../../shared/util/tool_name_normalization.dart';
import '../ai/index.dart';
import '../mcp/index.dart';
import '../plugin_service/index.dart';
import '../thread_template_runtime/index.dart';
import 'android_reverse_adb_client.dart';
import 'android_reverse_dialog_utils.dart';
import 'android_reverse_session_config.dart';
import 'android_reverse_session_controller.dart';
import 'android_reverse_toolchain_diagnostics.dart';

const Duration _kSwitchDuration = Duration(milliseconds: 220);
const Curve _kSwitchInCurve = Curves.easeOutCubic;
const double _kAdbInlineControlHeight = 44;
const double _kDashboardFilterControlHeight = 36;
const double _kDashboardActionButtonHeight = 36;
const double _kDashboardActionIconSize = 14;
const double _kDashboardIconActionButtonSize = 36;
const double _kDashboardIconActionIconSize = 17;
const double _kDashboardTrailingActionGap = 8;
const double _kDashboardHeaderCompactBreakpoint = 720;
const double _kDashboardHeaderLeadingMaxWidth = 320;
const double _kDashboardHeaderLeadingMaxWidthRatio = 0.34;
const double _kDeviceTrailingActionWidth = 88;
const double _kDashboardDialogMaxWidth = 960;
const double _kDashboardDialogMaxHeight = 720;
const double _kShellOutputMaxHeight = 220;
const double _kIconButtonGap = 8;
const EdgeInsets _kDashboardDialogInsetPadding = EdgeInsets.all(16);
const int _kDefaultLogcatLines = 200;
const int _kAutoLogcatLines = 80;
const int _kDefaultLogcatCacheLimit = 200;
const int _kMinLogcatCacheLimit = 50;
const int _kMaxLogcatCacheLimit = 2000;
const int _kShellHistoryLimit = 6;
const int _kPackageDumpsysSummaryMaxLines = 160;
const int _kDefaultScreenRecordSeconds = 10;
const int _kMcpToolPreviewLimit = 8;
const Duration _kInteractiveShellTimeout = Duration(seconds: 8);
const Duration _kPackageDumpsysTimeout = Duration(seconds: 12);
const Duration _kDeviceSnapshotTimeout = Duration(seconds: 8);
const Duration _kLogcatAutoRefreshInterval = Duration(seconds: 1);
const Duration _kLogcatFollowScrollDuration = Duration(milliseconds: 360);
const int _kDeviceSnapshotMaxLines = 80;
const int _kMinTcpPort = 1;
const int _kMaxTcpPort = 65535;
const String _kAdbShellHintZh = '请输入 adb shell 命令';
const String _kAdbShellHintEn = 'Enter adb shell command';
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
const List<String> _kAndroidMcpKeywords =
    TemplateRuntimeDependencyRegistry.androidReverseMcpKeywords;
const List<String> _kAndroidRuntimePluginIds =
    TemplateRuntimeDependencyRegistry.androidReversePluginIds;
Future<void> showAndroidReverseDashboardDialog(
  BuildContext context, {
  required AndroidReverseSessionController controller,
  required String sessionId,
}) {
  return showAndroidReverseToolDialog<void>(
    context: context,
    surfaceMotion: true,
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
  mcp,
  plugins,
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

enum _RuntimePluginAction {
  info,
  install,
  checkUpdate,
  update,
  enable,
  disable,
  uninstall,
}

enum _LogcatLineAction { copy, delete }

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
    descZh: 'JNI/so 入参与返回值',
    descEn: 'JNI/so args and return value',
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
      _Tab.mcp => 'MCP',
      _Tab.plugins => isZh ? '插件' : 'Plugins',
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
    _Tab.mcp => Icons.extension_rounded,
    _Tab.plugins => Icons.extension_outlined,
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
  final _logcatParseCache = <String, _ParsedLogcatLine>{};
  final _shellHistory = <String>[];
  Timer? _logcatTimer;
  final ScrollController _logcatScrollController = ScrollController();
  final TextEditingController _shellCtrl = TextEditingController();
  final TextEditingController _shellOutputCtrl = TextEditingController();
  final TextEditingController _wirelessEndpointCtrl = TextEditingController();
  final TextEditingController _forwardLocalCtrl = TextEditingController();
  final TextEditingController _forwardRemoteCtrl = TextEditingController();
  final TextEditingController _reverseDeviceCtrl = TextEditingController();
  final TextEditingController _reverseHostCtrl = TextEditingController();
  final TextEditingController _logcatFilterCtrl = TextEditingController();
  final TextEditingController _logcatPidCtrl = TextEditingController();
  final TextEditingController _installApkPathCtrl = TextEditingController();
  final TextEditingController _pushLocalCtrl = TextEditingController();
  final TextEditingController _pushRemoteCtrl = TextEditingController();
  final TextEditingController _pullRemoteCtrl = TextEditingController();
  final TextEditingController _pullLocalCtrl = TextEditingController();
  final TextEditingController _fridaScriptCtrl = TextEditingController();
  final TextEditingController _networkProxyHostCtrl = TextEditingController();
  final TextEditingController _networkProxyPortCtrl = TextEditingController();
  final TextEditingController _mitmCertPathCtrl = TextEditingController();
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
  bool _runningStaticAction = false;
  bool _runningFridaDoctor = false;
  bool _runningFridaAction = false;
  bool _runningNetworkProbe = false;
  bool _runningNetworkAction = false;
  bool _runningCertificateAction = false;
  bool _writingNetworkAddon = false;
  bool _writingCertificateArtifacts = false;
  bool _writingMcpArtifacts = false;
  bool _makingEvidenceBundle = false;
  bool _capturingLogcatSnapshot = false;
  bool _clearingLogcat = false;
  bool _savingLogcatFile = false;
  bool _loadingDeviceDetails = false;
  bool _savingFridaScript = false;
  bool _logcatPackageFilterEnabled = false;
  bool _logcatAutoRefresh = false;
  bool _logcatStickToBottom = true;
  bool _didKickInitialRefresh = false;
  String? _selectedDeviceSerial;
  String? _lastDeviceActionOutput;
  AdbCommandResult? _lastShellResult;
  AdbCommandResult? _lastDeviceActionResult;
  AdbCommandResult? _lastToolchainCommandResult;
  String? _logcatError;
  String _logcatLevel = 'V';
  int _logcatCacheLimit = _kDefaultLogcatCacheLimit;
  int _logcatMutationGeneration = 0;
  Map<String, String> _deviceProps = const <String, String>{};
  List<String> _forwardRows = const <String>[];
  List<String> _reverseRows = const <String>[];
  String? _deviceSnapshotOutput;
  List<String> _packages = const <String>[];
  List<AndroidReverseToolchainProbeResult> _toolchainRows =
      const <AndroidReverseToolchainProbeResult>[];
  final Set<String> _runningToolchainCommandIds = <String>{};
  List<AndroidProcess> _processes = const <AndroidProcess>[];
  String? _selectedPackageName;
  String? _packageAnalysisOutput;
  String? _selectedFridaSnippetAsset;
  String? _lastSavedFridaScriptPath;
  String? _fridaArtifactOutput;
  String? _staticQuickScanOutput;
  String? _logcatArtifactOutput;
  String? _networkAddonOutput;
  String? _certificateArtifactOutput;
  String? _mcpArtifactOutput;
  String? _evidenceBundleOutput;
  String _cryptoCopyValue = '';
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
    _networkProxyHostCtrl.text = '10.0.2.2';
    _networkProxyPortCtrl.text = '8080';
    _mitmCertPathCtrl.text = '~/.mitmproxy/mitmproxy-ca-cert.pem';
    _ctrl.addListener(_onControllerChanged);
    _fridaScriptCtrl.addListener(_onFridaScriptChanged);
    _logcatScrollController.addListener(_onLogcatScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didKickInitialRefresh) return;
    _didKickInitialRefresh = true;
    _refreshAll();
    unawaited(_refreshToolchain());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _fridaScriptCtrl.removeListener(_onFridaScriptChanged);
    _logcatScrollController.removeListener(_onLogcatScroll);
    _logcatTimer?.cancel();
    _logcatScrollController.dispose();
    _shellCtrl.dispose();
    _shellOutputCtrl.dispose();
    _wirelessEndpointCtrl.dispose();
    _forwardLocalCtrl.dispose();
    _forwardRemoteCtrl.dispose();
    _reverseDeviceCtrl.dispose();
    _reverseHostCtrl.dispose();
    _logcatFilterCtrl.dispose();
    _logcatPidCtrl.dispose();
    _installApkPathCtrl.dispose();
    _pushLocalCtrl.dispose();
    _pushRemoteCtrl.dispose();
    _pullRemoteCtrl.dispose();
    _pullLocalCtrl.dispose();
    _fridaScriptCtrl.dispose();
    _networkProxyHostCtrl.dispose();
    _networkProxyPortCtrl.dispose();
    _mitmCertPathCtrl.dispose();
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

  void _onLogcatScroll() {
    if (!_logcatScrollController.hasClients) return;
    final position = _logcatScrollController.position;
    final distanceToBottom = position.maxScrollExtent - position.pixels;
    final shouldStick = distanceToBottom <= 72;
    if (_logcatStickToBottom == shouldStick) return;
    _logcatStickToBottom = shouldStick;
  }

  void _setLogcatAutoRefresh(bool enabled) {
    if (_logcatAutoRefresh == enabled) return;
    setState(() => _logcatAutoRefresh = enabled);
    _logcatTimer?.cancel();
    _logcatTimer = null;
    if (!enabled) return;
    _logcatStickToBottom = true;
    unawaited(_fetchLogcat(append: _logcatLines.isNotEmpty, silent: true));
    _logcatTimer = startSafePeriodicTimer(_kLogcatAutoRefreshInterval, (_) {
      if (!mounted || !_logcatAutoRefresh || _loadingLogcat) return;
      unawaited(_fetchLogcat(append: true, silent: true));
    });
  }

  void _scheduleLogcatFollowScroll({bool force = false}) {
    if (!force && !_logcatStickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_logcatScrollController.hasClients) return;
      final position = _logcatScrollController.position;
      final target = position.maxScrollExtent;
      if ((target - position.pixels).abs() < 2) return;
      _logcatScrollController.animateTo(
        target,
        duration: _kLogcatFollowScrollDuration,
        curve: Curves.easeOutCubic,
      );
    });
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
        _showSnack(
          isZh ? '已生成 APP 信息报告工件。' : 'APP report artifacts saved.',
          kind: OpenHandSnackKind.success,
          duration: const Duration(seconds: 3),
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
      return trimRightNonEmptyLines(
        raw.split('\n'),
        limit: _kPackageDumpsysSummaryMaxLines,
      ).join('\n');
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
          _reverseRows = const <String>[];
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
      final reversesFuture = _ctrl.listReverses(serial: serial);
      final snapshotFuture = _ctrl.shellDetailed(
        _kDeviceSnapshotScript,
        serial: serial,
        timeout: _kDeviceSnapshotTimeout,
      );
      final props = await propsFuture;
      final forwards = await forwardsFuture;
      final reverses = await reversesFuture;
      final snapshot = await snapshotFuture;
      if (!mounted) return;
      setState(() {
        _deviceProps = props;
        _forwardRows = splitTrimmedNonEmpty(forwards ?? '', separator: '\n');
        _reverseRows = splitTrimmedNonEmpty(reverses ?? '', separator: '\n');
        _deviceSnapshotOutput = _formatDeviceSnapshot(snapshot, isZh);
      });
    } catch (error) {
      if (!mounted) return;
      final isZh = openHandIsChineseLocale(context);
      setState(() {
        _deviceSnapshotOutput = isZh
            ? '刷新设备详情失败：$error'
            : 'Failed to refresh device details: $error';
      });
    } finally {
      if (mounted) setState(() => _loadingDeviceDetails = false);
    }
  }

  String? _formatDeviceSnapshot(AdbCommandResult result, bool isZh) {
    final lines = trimRightNonEmptyLines(
      result.stdout.split('\n'),
      limit: _kDeviceSnapshotMaxLines,
    );
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

  Future<void> _fetchLogcat({bool append = false, bool silent = false}) async {
    if (_loadingLogcat) return;
    final generation = _logcatMutationGeneration;
    setState(() {
      _loadingLogcat = true;
      if (!silent) _logcatError = null;
    });
    try {
      final isZh = openHandIsChineseLocale(context);
      final tag = _logcatFilterCtrl.text.trim();
      final pidFilter = await _resolveLogcatPidFilter(isZh: isZh);
      final result = await _ctrl.logcatDetailed(
        lines: append ? _kAutoLogcatLines : _kDefaultLogcatLines,
        tag: tag.isEmpty ? null : tag,
        level: _logcatLevel,
        pid: pidFilter.pid,
        serial: _targetSerial,
      );
      if (mounted && generation == _logcatMutationGeneration) {
        final incoming = result.stdout
            .split('\n')
            .map(_sanitizeLogcatLine)
            .where(_hasVisibleLogcatText)
            .toList(growable: false);
        final err = result.stderr.trim();
        final added = append
            ? _appendLogcatTail(incoming)
            : _replaceLogcatLines(incoming);
        setState(() {
          if (incoming.isNotEmpty && result.timedOut) {
            _logcatError = isZh
                ? 'Logcat 读取超时，已展示可用输出。'
                : 'Logcat timed out; usable output is shown.';
          } else if (incoming.isNotEmpty && pidFilter.notice != null) {
            _logcatError = pidFilter.notice;
          } else if (incoming.isNotEmpty) {
            if (!silent || added > 0) _logcatError = null;
          } else if (err.isNotEmpty) {
            _logcatError = err;
          } else if (!silent && !append) {
            _logcatError = isZh
                ? '没有读取到 Logcat 输出。请确认设备在线，或清空 Tag 过滤后重试。'
                : 'No Logcat output was read. Check the device or clear the tag filter and retry.';
          }
        });
        if (added > 0 || !append) {
          _scheduleLogcatFollowScroll(force: !append || _logcatAutoRefresh);
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (!append) _logcatLines.clear();
        if (!silent || !append) _logcatError = '$error';
      });
    } finally {
      if (mounted) setState(() => _loadingLogcat = false);
    }
  }

  int _replaceLogcatLines(List<String> lines) {
    _logcatLines
      ..clear()
      ..addAll(_trimLogcatBuffer(lines));
    _compactLogcatParseCache();
    return _logcatLines.length;
  }

  int _appendLogcatTail(List<String> incoming) {
    if (incoming.isEmpty) return 0;
    if (_logcatLines.isEmpty) {
      _logcatLines.addAll(_trimLogcatBuffer(incoming));
      return _logcatLines.length;
    }
    final overlap = _tailHeadOverlap(_logcatLines, incoming);
    final additions = incoming.skip(overlap).toList(growable: false);
    if (additions.isEmpty) return 0;
    _logcatLines.addAll(additions);
    final overflow = _logcatLines.length - _logcatCacheLimit;
    if (overflow > 0) {
      _logcatLines.removeRange(0, overflow);
    }
    _compactLogcatParseCache();
    return additions.length;
  }

  List<String> _trimLogcatBuffer(List<String> lines) {
    if (lines.length <= _logcatCacheLimit) return lines;
    return lines.sublist(lines.length - _logcatCacheLimit);
  }

  void _compactLogcatParseCache() {
    final maxCacheSize = _logcatCacheLimit * 3;
    if (_logcatParseCache.length <= maxCacheSize) return;
    final visible = _logcatLines.toSet();
    _logcatParseCache.removeWhere((line, _) => !visible.contains(line));
  }

  int _tailHeadOverlap(List<String> existing, List<String> incoming) {
    final max = existing.length < incoming.length
        ? existing.length
        : incoming.length;
    for (var len = max; len > 0; len--) {
      var matched = true;
      for (var i = 0; i < len; i++) {
        if (existing[existing.length - len + i] != incoming[i]) {
          matched = false;
          break;
        }
      }
      if (matched) return len;
    }
    return 0;
  }

  Future<void> _clearLogcat() async {
    if (_clearingLogcat) return;
    final isZh = openHandIsChineseLocale(context);
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '清空 Logcat？' : 'Clear Logcat?',
      message: isZh
          ? '将清空当前面板日志，并尝试清空设备 Logcat 缓冲区。自动刷新开启时会继续读取清空后的新日志。'
          : 'This clears the panel logs and tries to clear the device logcat buffer. Auto refresh will continue reading new logs afterwards.',
      cancelLabel: isZh ? '取消' : 'Cancel',
      confirmLabel: isZh ? '清空' : 'Clear',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _clearingLogcat = true;
      _logcatLines.clear();
      _logcatParseCache.clear();
      _logcatMutationGeneration++;
      _logcatError = isZh ? '正在清空设备 Logcat...' : 'Clearing device logcat...';
    });
    try {
      final result = await _ctrl.clearLogcatDetailed(serial: _targetSerial);
      if (!mounted) return;
      setState(() {
        _logcatError = result.ok
            ? (isZh ? '已清空设备 Logcat。' : 'Device logcat was cleared.')
            : _formatAdbResult(result);
      });
    } catch (error) {
      if (!mounted) return;
      final isZh = openHandIsChineseLocale(context);
      setState(() {
        _logcatError =
            '${isZh ? "清空 Logcat 失败" : "Failed to clear logcat"}: $error';
      });
    } finally {
      if (mounted) setState(() => _clearingLogcat = false);
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

  _ParsedLogcatLine _parseLogcatLine(String raw) {
    final line = raw.trimRight();
    final timeMatch = RegExp(
      r'^(\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+([^:]+):\s?(.*)$',
    ).firstMatch(line);
    if (timeMatch != null) {
      return _ParsedLogcatLine(
        raw: line,
        level: timeMatch.group(4),
        time: timeMatch.group(1),
        pid: timeMatch.group(2),
        tid: timeMatch.group(3),
        tag: timeMatch.group(5)?.trim(),
        message: timeMatch.group(6)?.trimRight() ?? '',
      );
    }
    final briefMatch = RegExp(
      r'^([VDIWEF])\/([^(]+)\(\s*(\d+)\):\s?(.*)$',
    ).firstMatch(line);
    if (briefMatch != null) {
      return _ParsedLogcatLine(
        raw: line,
        level: briefMatch.group(1),
        pid: briefMatch.group(3),
        tag: briefMatch.group(2)?.trim(),
        message: briefMatch.group(4)?.trimRight() ?? '',
      );
    }
    return _ParsedLogcatLine(
      raw: line,
      level: _fallbackLogcatLevel(line),
      message: line,
    );
  }

  String? _fallbackLogcatLevel(String line) {
    final spaced = RegExp(r'\s([VDIWEF])\s').firstMatch(line);
    if (spaced != null) return spaced.group(1);
    final slash = RegExp(r'\b([VDIWEF])\/').firstMatch(line);
    return slash?.group(1);
  }

  _ParsedLogcatLine _parseCachedLogcatLine(String raw) {
    return _logcatParseCache.putIfAbsent(raw, () => _parseLogcatLine(raw));
  }

  String _logcatLevelOptionLabel(String level, bool isZh) {
    return switch (level) {
      'V' => isZh ? '详细' : 'Verbose',
      'D' => isZh ? '调试' : 'Debug',
      'I' => isZh ? '信息' : 'Info',
      'W' => isZh ? '警告' : 'Warning',
      'E' => isZh ? '错误' : 'Error',
      'F' => isZh ? '致命' : 'Fatal',
      _ => level,
    };
  }

  Future<void> _showLogcatLineMenu(
    int index,
    String line,
    Offset position,
    bool isZh,
  ) async {
    if (!mounted) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = await showMenu<_LogcatLineAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<_LogcatLineAction>(
          value: _LogcatLineAction.copy,
          child: Row(
            children: [
              const Icon(Icons.copy_rounded, size: 16),
              const SizedBox(width: 8),
              Text(isZh ? '复制日志' : 'Copy log'),
            ],
          ),
        ),
        PopupMenuItem<_LogcatLineAction>(
          value: _LogcatLineAction.delete,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(isZh ? '删除此条' : 'Delete row'),
            ],
          ),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case _LogcatLineAction.copy:
        await _copyText(line);
      case _LogcatLineAction.delete:
        if (index < 0 || index >= _logcatLines.length) return;
        setState(() {
          _logcatLines.removeAt(index);
          _logcatMutationGeneration++;
          _compactLogcatParseCache();
        });
    }
  }

  Future<void> _saveLogcatSnapshot() async {
    if (_logcatLines.isEmpty || _savingLogcatFile) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() => _savingLogcatFile = true);
    String? path;
    Object? failure;
    try {
      path = await _saveTextWithPicker(
        suggestedName: 'openhand-logcat-${_fileTimestamp()}.log',
        typeLabel: 'LOG',
        extensions: const <String>['log', 'txt'],
        content: '${_logcatLines.join('\n')}\n',
      );
    } catch (error) {
      failure = error;
    } finally {
      if (mounted) setState(() => _savingLogcatFile = false);
    }
    if (!mounted) return;
    if (failure != null) {
      _showSnack(
        '${isZh ? "保存 Logcat 失败" : "Failed to save Logcat"}: $failure',
      );
    } else if (path != null) {
      _showSnack(
        isZh
            ? '已保存 ${_logcatLines.length} 行到 $path'
            : 'Saved ${_logcatLines.length} lines to $path',
      );
    }
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
      final pidFilter = await _resolveLogcatPidFilter(isZh: isZh);
      final result = await _ctrl.captureLogcatSnapshotToArtifacts(
        tag: tag.isEmpty ? null : tag,
        level: _logcatLevel,
        pid: pidFilter.pid,
        packageName: pidFilter.packageName,
        serial: _targetSerial,
        lines: _kDefaultLogcatLines,
      );
      if (!mounted) return;
      final formattedResult = _formatAdbResult(result);
      setState(() {
        _logcatArtifactOutput = <String>[
          if (pidFilter.notice != null) pidFilter.notice!,
          if (formattedResult.trim().isNotEmpty) formattedResult,
        ].join('\n\n');
        if (pidFilter.notice != null) {
          _logcatError = pidFilter.notice;
        } else if (!result.ok && !result.partialOk) {
          _logcatError = _logcatArtifactOutput;
        }
      });
      if (result.ok || result.partialOk) {
        _showSnack(
          isZh ? '已生成 Logcat 快照工件。' : 'Logcat snapshot artifacts saved.',
          kind: OpenHandSnackKind.success,
          duration: const Duration(seconds: 3),
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

  Future<({String? pid, String? notice, String? packageName})>
  _resolveLogcatPidFilter({required bool isZh}) async {
    final explicitPid = _logcatPidCtrl.text.trim();
    final packageName = _logcatPackageFilterEnabled
        ? _logcatPackageTarget()
        : null;
    final explicitPidValid = RegExp(r'^\d+$').hasMatch(explicitPid);
    if (explicitPidValid) {
      return (pid: explicitPid, notice: null, packageName: packageName);
    }
    if (explicitPid.isNotEmpty) {
      return (
        pid: null,
        notice: isZh
            ? 'PID 只能填写数字，已忽略该 PID 过滤。'
            : 'PID must be numeric; PID filter was ignored.',
        packageName: packageName,
      );
    }
    if (packageName == null) {
      return (pid: null, notice: null, packageName: null);
    }
    final lookup = await _ctrl.pidOfPackageDetailed(
      packageName,
      serial: _targetSerial,
    );
    final pid = lookup.pid?.trim();
    if (pid != null && pid.isNotEmpty) {
      return (pid: pid, notice: null, packageName: packageName);
    }
    return (
      pid: null,
      notice: _logcatPidLookupNotice(lookup, isZh: isZh),
      packageName: packageName,
    );
  }

  String _logcatPidLookupNotice(
    AndroidPackagePidLookupResult lookup, {
    required bool isZh,
  }) {
    final stderr = lookup.stderr.trim();
    if (lookup.timedOut) {
      return isZh
          ? '解析目标包 PID 超时，已按当前等级读取全局 Logcat。'
          : 'Resolving the target package PID timed out; loaded global logcat with the selected level.';
    }
    if (stderr.isNotEmpty) {
      return isZh
          ? '解析目标包 PID 失败：$stderr。已按当前等级读取全局 Logcat。'
          : 'Failed to resolve the target package PID: $stderr. Loaded global logcat with the selected level.';
    }
    return isZh
        ? '目标包未运行或无法解析 PID，已按当前等级读取全局 Logcat。'
        : 'Target package is not running or PID was unavailable; loaded global logcat with the selected level.';
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
        _showSnack(
          isZh
              ? '静态扫描失败，已展示错误输出。'
              : 'Static scan failed. Error output is shown.',
          kind: OpenHandSnackKind.error,
          duration: const Duration(seconds: 3),
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
          isZh ? '已生成网络抓包工件:' : 'Generated network capture artifacts:',
          addonPath,
          'README: ${_ctrl.networkReadmePath}',
          'Proxy probe: ${_ctrl.networkProxyProbeScriptPath}',
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
      _showSnack(
        isZh ? '生成 mitmproxy addon 失败。' : 'Failed to generate mitmproxy addon.',
        kind: OpenHandSnackKind.error,
        duration: const Duration(seconds: 3),
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
      _showSnack(
        isZh ? '生成证书工件失败。' : 'Failed to generate certificate artifacts.',
        kind: OpenHandSnackKind.error,
        duration: const Duration(seconds: 3),
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
      _showSnack(
        isZh ? '生成 MCP 联动工件失败。' : 'Failed to generate MCP linkage artifacts.',
        kind: OpenHandSnackKind.error,
        duration: const Duration(seconds: 3),
      );
    } finally {
      if (mounted) setState(() => _writingMcpArtifacts = false);
    }
  }

  Future<void> _makeEvidenceBundle() async {
    if (_makingEvidenceBundle) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _makingEvidenceBundle = true;
      _evidenceBundleOutput = isZh ? '生成中...' : 'Generating...';
    });
    try {
      final result = await _ctrl.makeEvidenceBundleToArtifacts();
      if (!mounted) return;
      setState(() => _evidenceBundleOutput = _formatAdbResult(result));
      OpenHandSnackBar.showInfo(
        context,
        result.ok
            ? (isZh ? '证据包已生成。' : 'Evidence bundle generated.')
            : (isZh ? '证据包生成失败。' : 'Evidence bundle generation failed.'),
      );
    } finally {
      if (mounted) setState(() => _makingEvidenceBundle = false);
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
      _showSnack(
        isZh
            ? '加载 Frida snippet 失败：$error'
            : 'Failed to load Frida snippet: $error',
        kind: OpenHandSnackKind.error,
        duration: const Duration(seconds: 3),
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
      setState(() {
        _lastSavedFridaScriptPath = _extractFridaScriptPath(result.stdout);
        _fridaArtifactOutput = _formatAdbResult(result);
      });
      if (result.ok) {
        _showSnack(
          isZh ? '已保存 Frida 脚本工件。' : 'Frida script artifact saved.',
          kind: OpenHandSnackKind.success,
          duration: const Duration(seconds: 3),
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

  Future<void> _runFridaDoctor() async {
    if (_runningFridaDoctor) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _runningFridaDoctor = true;
      _fridaArtifactOutput = isZh
          ? 'Frida 诊断运行中...'
          : 'Running Frida doctor...';
    });
    try {
      await _ctrl.ensureMcpLinkageArtifacts();
      final pkg = _logcatPackageTarget();
      final serial = _targetSerial?.trim();
      final result = await _ctrl.runLocalArtifactScriptDetailed(
        scriptPath: _ctrl.fridaDoctorScriptPath,
        args: <String>[
          '--timeout',
          '6',
          if (pkg != null && pkg.isNotEmpty) ...['--package', pkg],
          if (serial != null && serial.isNotEmpty) ...['-s', serial],
        ],
        timeout: const Duration(seconds: 15),
        displayCommand:
            'bash ${_shellQuote(_ctrl.fridaDoctorScriptPath)} --timeout 6${pkg == null ? "" : " --package ${_shellQuote(pkg)}"}',
        tag: 'android_reverse.frida_doctor',
      );
      if (!mounted) return;
      setState(() => _fridaArtifactOutput = _formatAdbResult(result));
    } finally {
      if (mounted) setState(() => _runningFridaDoctor = false);
    }
  }

  Future<String?> _ensureFridaScriptPath() async {
    final cached = _lastSavedFridaScriptPath?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    final script = _fridaScriptCtrl.text.trim();
    if (script.isEmpty) return null;
    final result = await _ctrl.saveFridaScriptToArtifacts(
      script: _fridaScriptCtrl.text,
      presetAssetPath: _selectedFridaSnippetAsset,
      packageName: _logcatPackageTarget(),
    );
    final path = _extractFridaScriptPath(result.stdout);
    if (mounted) {
      setState(() {
        _lastSavedFridaScriptPath = path;
        _fridaArtifactOutput = _formatAdbResult(result);
      });
    }
    return path;
  }

  String? _extractFridaScriptPath(String text) {
    final match = RegExp(r'Frida script:\s*(.+)').firstMatch(text);
    final path = match?.group(1)?.trim();
    return path == null || path.isEmpty ? null : path;
  }

  Future<void> _runFridaCapture({required bool spawn}) async {
    if (_runningFridaAction) return;
    final isZh = openHandIsChineseLocale(context);
    final pkg = _logcatPackageTarget();
    if (pkg == null || pkg.isEmpty) {
      _showSnack(isZh ? '请先选择或配置包名。' : 'Select or configure a package first.');
      return;
    }
    setState(() {
      _runningFridaAction = true;
      _fridaArtifactOutput = isZh
          ? 'Frida 注入执行中...'
          : 'Running Frida capture...';
    });
    try {
      await _ctrl.ensureMcpLinkageArtifacts();
      final scriptPath = await _ensureFridaScriptPath();
      if (scriptPath == null || scriptPath.isEmpty) {
        if (mounted) {
          setState(() {
            _fridaArtifactOutput = isZh
                ? '请先选择 snippet 或保存脚本。'
                : 'Load a snippet or save a script first.';
          });
        }
        return;
      }
      final serial = _targetSerial?.trim();
      final result = await _ctrl.runLocalArtifactScriptDetailed(
        scriptPath: _ctrl.fridaCaptureScriptPath,
        args: <String>[
          '--package',
          pkg,
          '--script',
          scriptPath,
          spawn ? '--spawn' : '--attach',
          if (serial != null && serial.isNotEmpty) ...['-s', serial],
        ],
        timeout: const Duration(seconds: 28),
        displayCommand:
            'bash ${_shellQuote(_ctrl.fridaCaptureScriptPath)} --package ${_shellQuote(pkg)} --script ${_shellQuote(scriptPath)} ${spawn ? "--spawn" : "--attach"}',
        tag: spawn
            ? 'android_reverse.frida_spawn_capture'
            : 'android_reverse.frida_attach_capture',
      );
      if (!mounted) return;
      setState(() => _fridaArtifactOutput = _formatAdbResult(result));
    } finally {
      if (mounted) setState(() => _runningFridaAction = false);
    }
  }

  Future<void> _readFridaArtifacts() async {
    if (_runningFridaAction) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _runningFridaAction = true;
      _fridaArtifactOutput = isZh
          ? '读取 Frida 工件中...'
          : 'Reading Frida artifacts...';
    });
    try {
      await _ctrl.ensureMcpLinkageArtifacts();
      final result = await _ctrl.runLocalShellDetailed(
        actionName: 'frida-read-artifacts',
        command: r'''
set +e
printf '[scripts]\n'
find "$FRIDA_SCRIPTS_DIR" -maxdepth 1 -type f 2>/dev/null | sort | tail -40
printf '\n[output]\n'
find "$FRIDA_OUTPUT_DIR" -maxdepth 1 -type f 2>/dev/null | sort | tail -40
latest="$(find "$FRIDA_OUTPUT_DIR" -maxdepth 1 -type f 2>/dev/null | sort | tail -1)"
if [ -n "$latest" ]; then
  printf '\n[latest:%s]\n' "$latest"
  tail -160 "$latest"
fi
''',
        environment: <String, String>{
          'FRIDA_SCRIPTS_DIR': _ctrl.fridaScriptsDir,
          'FRIDA_OUTPUT_DIR': _ctrl.fridaOutputDir,
        },
        timeout: const Duration(seconds: 8),
        displayCommand: 'read Frida artifacts',
        tag: 'android_reverse.frida_read_artifacts',
      );
      if (!mounted) return;
      setState(() => _fridaArtifactOutput = _formatAdbResult(result));
    } finally {
      if (mounted) setState(() => _runningFridaAction = false);
    }
  }

  Future<void> _startExistingFridaServer() async {
    if (_runningFridaAction) return;
    final isZh = openHandIsChineseLocale(context);
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '启动设备端 frida-server？' : 'Start device frida-server?',
      message: isZh
          ? '仅会尝试启动已存在的 /data/local/tmp/frida-server 并建立 27042 端口转发，不会自动下载或推送二进制。'
          : 'This only starts an existing /data/local/tmp/frida-server and forwards port 27042. It will not download or push binaries.',
      cancelLabel: isZh ? '取消' : 'Cancel',
      confirmLabel: isZh ? '启动' : 'Start',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _runningFridaAction = true;
      _fridaArtifactOutput = isZh
          ? '启动 frida-server 中...'
          : 'Starting frida-server...';
    });
    try {
      final start = await _ctrl.shellDetailed(
        'if [ -x /data/local/tmp/frida-server ]; then pidof frida-server >/dev/null 2>&1 || nohup /data/local/tmp/frida-server >/dev/null 2>&1 & echo started; else echo missing:/data/local/tmp/frida-server; exit 2; fi',
        serial: _targetSerial,
        timeout: const Duration(seconds: 8),
      );
      final forward = await _ctrl.forwardPortDetailed(
        27042,
        27042,
        serial: _targetSerial,
      );
      final output = <String>[
        _formatAdbResult(start),
        '',
        _formatAdbResult(forward),
      ].join('\n');
      if (!mounted) return;
      setState(() => _fridaArtifactOutput = output);
    } finally {
      if (mounted) setState(() => _runningFridaAction = false);
    }
  }

  Future<void> _runNetworkProxyProbe() async {
    if (_runningNetworkProbe) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _runningNetworkProbe = true;
      _networkAddonOutput = isZh
          ? '代理 / 证书预检运行中...'
          : 'Running proxy / cert preflight...';
    });
    try {
      await _ctrl.ensureMitmproxyJsonlAddon();
      final serial = _targetSerial?.trim();
      final result = await _ctrl.runLocalArtifactScriptDetailed(
        scriptPath: _ctrl.networkProxyProbeScriptPath,
        args: const <String>['--timeout', '6'],
        environment: <String, String>{
          if (serial != null && serial.isNotEmpty) 'ADB_SERIAL': serial,
          if (_logcatPackageTarget() != null)
            'ANDROID_PACKAGE_NAME': _logcatPackageTarget()!,
        },
        timeout: const Duration(seconds: 18),
        displayCommand:
            'bash ${_shellQuote(_ctrl.networkProxyProbeScriptPath)} --timeout 6',
        tag: 'android_reverse.network_proxy_probe',
      );
      if (!mounted) return;
      setState(() => _networkAddonOutput = _formatAdbResult(result));
    } finally {
      if (mounted) setState(() => _runningNetworkProbe = false);
    }
  }

  Future<void> _runNetworkAction(
    Future<AdbCommandResult> Function() action,
  ) async {
    if (_runningNetworkAction) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _runningNetworkAction = true;
      _networkAddonOutput = isZh ? '网络动作执行中...' : 'Running network action...';
    });
    try {
      final result = await action();
      if (!mounted) return;
      setState(() => _networkAddonOutput = _formatAdbResult(result));
    } finally {
      if (mounted) setState(() => _runningNetworkAction = false);
    }
  }

  int? _networkProxyPort() {
    final value = optionalIntFromValue(_networkProxyPortCtrl.text);
    if (value == null || value < _kMinTcpPort || value > _kMaxTcpPort) {
      return null;
    }
    return value;
  }

  String? _networkProxyHost() {
    final host = _networkProxyHostCtrl.text.trim();
    if (host.isEmpty || host.length > 255) return null;
    if (!RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(host)) return null;
    return host;
  }

  Future<void> _startNetworkCapture() async {
    final isZh = openHandIsChineseLocale(context);
    final port = _networkProxyPort();
    if (port == null) {
      _showSnack(isZh ? '请输入合法端口。' : 'Enter a valid port.');
      return;
    }
    await _runNetworkAction(() => _ctrl.startNetworkCapture(port: port));
  }

  Future<void> _setDeviceProxy() async {
    final isZh = openHandIsChineseLocale(context);
    final host = _networkProxyHost();
    final port = _networkProxyPort();
    if (host == null || port == null) {
      _showSnack(isZh ? '请输入合法代理主机和端口。' : 'Enter a valid proxy host and port.');
      return;
    }
    await _runNetworkAction(
      () => _ctrl.shellDetailed(
        'settings put global http_proxy ${_shellQuote('$host:$port')}; settings get global http_proxy',
        serial: _targetSerial,
        timeout: const Duration(seconds: 8),
      ),
    );
  }

  Future<void> _readDeviceProxy() {
    return _runNetworkAction(
      () => _ctrl.shellDetailed(
        'settings get global http_proxy; settings get global global_http_proxy_host 2>/dev/null; settings get global global_http_proxy_port 2>/dev/null',
        serial: _targetSerial,
        timeout: const Duration(seconds: 8),
      ),
    );
  }

  Future<void> _clearDeviceProxy() {
    return _runNetworkAction(
      () => _ctrl.shellDetailed(
        'settings delete global http_proxy; settings delete global global_http_proxy_host 2>/dev/null; settings delete global global_http_proxy_port 2>/dev/null; settings get global http_proxy',
        serial: _targetSerial,
        timeout: const Duration(seconds: 8),
      ),
    );
  }

  Future<void> _exportNetworkFlowsWithPicker() async {
    if (_runningNetworkAction) return;
    final isZh = openHandIsChineseLocale(context);
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'openhand-mitm-flows-${_fileTimestamp()}.txt',
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'TXT', extensions: <String>['txt', 'log']),
        ],
      );
    } catch (error) {
      _showSnack(
        '${isZh ? "打开保存对话框失败" : "Failed to open save dialog"}: $error',
      );
      return;
    }
    if (location == null || !mounted) return;
    final destination = location.path;
    await _runNetworkAction(() async {
      final result = await _ctrl.exportMitmproxyFlows();
      if (!result.ok && !result.partialOk) return result;
      final source = File('${_ctrl.networkDir}/flows.txt');
      if (!await source.exists()) {
        return AdbCommandResult(
          args: const <String>['network-capture-export'],
          exitCode: -1,
          stdout: result.stdout,
          stderr: isZh
              ? 'mitmproxy flows 文本产物不存在。'
              : 'mitmproxy flows text artifact does not exist.',
          displayCommand: result.displayCommand,
        );
      }
      await source.copy(destination);
      return AdbCommandResult(
        args: const <String>['network-capture-export'],
        exitCode: result.exitCode,
        stdout: '${result.stdout.trimRight()}\nexported=$destination',
        stderr: result.stderr,
        timedOut: result.timedOut,
        displayCommand: result.displayCommand,
      );
    });
  }

  Future<void> _runStaticAction(
    Future<AdbCommandResult> Function() action,
  ) async {
    if (_runningStaticAction) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _runningStaticAction = true;
      _staticQuickScanOutput = isZh
          ? '静态分析动作执行中...'
          : 'Running static analysis action...';
    });
    try {
      final result = await action();
      if (!mounted) return;
      setState(() => _staticQuickScanOutput = _formatAdbResult(result));
    } finally {
      if (mounted) setState(() => _runningStaticAction = false);
    }
  }

  String? _mitmCertPathArg() {
    final value = _mitmCertPathCtrl.text.trim();
    if (value.isEmpty || value == '~/.mitmproxy/mitmproxy-ca-cert.pem') {
      return null;
    }
    return value;
  }

  Future<void> _runCertificateArtifactScript({
    required String scriptPath,
    required List<String> args,
    required String displayCommand,
  }) async {
    if (_runningCertificateAction) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _runningCertificateAction = true;
      _certificateArtifactOutput = isZh
          ? '证书动作执行中...'
          : 'Running certificate action...';
    });
    try {
      await _ctrl.ensureCertificateArtifacts(
        packageName: _logcatPackageTarget(),
      );
      final serial = _targetSerial?.trim();
      final result = await _ctrl.runLocalArtifactScriptDetailed(
        scriptPath: scriptPath,
        args: args,
        environment: <String, String>{
          if (serial != null && serial.isNotEmpty) 'ADB_SERIAL': serial,
        },
        displayCommand: displayCommand,
        tag: 'android_reverse.certificate_action',
      );
      if (!mounted) return;
      setState(() => _certificateArtifactOutput = _formatAdbResult(result));
    } finally {
      if (mounted) setState(() => _runningCertificateAction = false);
    }
  }

  Future<void> _generateDebugKeystore() {
    return _runCertificateArtifactScript(
      scriptPath: _ctrl.generateDebugKeystoreScriptPath,
      args: const <String>[],
      displayCommand:
          'bash ${_shellQuote(_ctrl.generateDebugKeystoreScriptPath)}',
    );
  }

  Future<void> _verifyConfiguredApkSignature() async {
    final apkPath = _ctrl.config.apkPath?.trim();
    final isZh = openHandIsChineseLocale(context);
    if (apkPath == null || apkPath.isEmpty) {
      _showSnack(isZh ? '当前会话未配置 APK 路径。' : 'No APK path is configured.');
      return;
    }
    await _runCertificateArtifactScript(
      scriptPath: _ctrl.verifyApkSignatureScriptPath,
      args: <String>[apkPath],
      displayCommand:
          'bash ${_shellQuote(_ctrl.verifyApkSignatureScriptPath)} ${_shellQuote(apkPath)}',
    );
  }

  Future<void> _readCertificateArtifacts() async {
    if (_runningCertificateAction) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _runningCertificateAction = true;
      _certificateArtifactOutput = isZh
          ? '读取证书工件中...'
          : 'Reading certificate artifacts...';
    });
    try {
      final result = await _ctrl.readCertificateArtifacts(
        packageName: _logcatPackageTarget(),
      );
      if (!mounted) return;
      setState(() => _certificateArtifactOutput = _formatAdbResult(result));
    } finally {
      if (mounted) setState(() => _runningCertificateAction = false);
    }
  }

  Future<void> _inspectMitmproxyCa() async {
    if (_runningCertificateAction) return;
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _runningCertificateAction = true;
      _certificateArtifactOutput = isZh
          ? '检查 CA 证书中...'
          : 'Inspecting CA certificate...';
    });
    try {
      final result = await _ctrl.inspectMitmproxyCa(
        certPath: _mitmCertPathArg(),
      );
      if (!mounted) return;
      setState(() => _certificateArtifactOutput = _formatAdbResult(result));
    } finally {
      if (mounted) setState(() => _runningCertificateAction = false);
    }
  }

  Future<void> _installMitmproxySystemCa() async {
    if (_runningCertificateAction) return;
    final isZh = openHandIsChineseLocale(context);
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '安装系统 CA？' : 'Install system CA?',
      message: isZh
          ? '此操作会执行 adb root/remount，并把 mitmproxy CA 写入系统证书目录。仅在测试设备、root/Magisk 环境中使用。'
          : 'This runs adb root/remount and writes the mitmproxy CA into the system cert store. Use only on rooted test devices.',
      cancelLabel: isZh ? '取消' : 'Cancel',
      confirmLabel: isZh ? '安装' : 'Install',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _runningCertificateAction = true;
      _certificateArtifactOutput = isZh
          ? '安装系统 CA 中...'
          : 'Installing system CA...';
    });
    try {
      final result = await _ctrl.installMitmproxyCaAsSystemCert(
        certPath: _mitmCertPathArg(),
        serial: _targetSerial,
      );
      if (!mounted) return;
      setState(() => _certificateArtifactOutput = _formatAdbResult(result));
    } finally {
      if (mounted) setState(() => _runningCertificateAction = false);
    }
  }

  Future<void> _runShell() async {
    final rawCmd = _shellCtrl.text.trim();
    final cmd = _normalizeAdbShellInput(rawCmd);
    if (_runningShell) return;
    final isZh = openHandIsChineseLocale(context);
    if (cmd.isEmpty) {
      final message = isZh
          ? '请输入要执行的 adb shell 命令。'
          : 'Enter an adb shell command to run.';
      setState(() => _shellOutputCtrl.text = message);
      OpenHandSnackBar.showInfo(context, message);
      return;
    }
    final serial = _targetSerial;
    setState(() {
      _runningShell = true;
      _lastShellResult = null;
      _rememberShellCommand(cmd);
      _shellOutputCtrl.text =
          '${isZh ? "执行中" : "Running"}: $cmd\n'
          '${isZh ? "目标设备" : "Target"}: ${_shellTargetLabel(serial, isZh)}\n'
          '${isZh ? "超时" : "Timeout"}: ${_kInteractiveShellTimeout.inSeconds}s';
    });
    try {
      final result = await _ctrl.shellDetailed(
        cmd,
        serial: serial,
        timeout: _kInteractiveShellTimeout,
      );
      if (!mounted) return;
      final output = _formatAdbResult(result);
      setState(() {
        _lastShellResult = result;
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

  void _rememberShellCommand(String command) {
    final normalized = command.trim();
    if (normalized.isEmpty) return;
    _shellHistory.removeWhere((entry) => entry == normalized);
    _shellHistory.insert(0, normalized);
    if (_shellHistory.length > _kShellHistoryLimit) {
      _shellHistory.removeRange(_kShellHistoryLimit, _shellHistory.length);
    }
  }

  String _shellTargetLabel(String? serial, bool isZh) {
    final value = serial?.trim();
    if (value == null || value.isEmpty) {
      return isZh ? '默认设备' : 'default device';
    }
    return value;
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
    final isZh = openHandIsChineseLocale(context);
    setState(() {
      _runningDeviceAction = true;
      _lastDeviceActionResult = null;
      _lastDeviceActionOutput = isZh ? '执行中...' : 'Running...';
    });
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        _lastDeviceActionResult = result;
        _lastDeviceActionOutput = _formatAdbResult(result);
        _runningDeviceAction = false;
      });
      unawaited(_refreshDeviceStateAfterAction());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lastDeviceActionResult = null;
        _lastDeviceActionOutput =
            '${openHandIsChineseLocale(context) ? "执行失败" : "Run failed"}: $error';
        _runningDeviceAction = false;
      });
    }
  }

  Future<void> _refreshDeviceStateAfterAction() async {
    await _doRefreshDevices();
    if (!mounted) return;
    await _refreshDeviceDetails();
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      OpenHandSnackBar.showSuccess(
        context,
        openHandIsChineseLocale(context) ? '已复制' : 'Copied',
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

    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: _kDashboardDialogMaxWidth,
      insetPadding: _kDashboardDialogInsetPadding,
      clipBehavior: Clip.hardEdge,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _kDashboardDialogMaxWidth,
          maxHeight: _kDashboardDialogMaxHeight,
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
                      if (tab == _Tab.plugins && _toolchainRows.isEmpty) {
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
      _Tab.mcp => _buildMcpTab(cs, theme, isZh),
      _Tab.plugins => _buildPluginsTab(cs, theme, isZh),
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
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      isZh ? '已检测设备' : 'Detected devices',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_targetSerial != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
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
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: _kDeviceTrailingActionWidth,
                child: _DashboardActionButton(
                  onPressed: () {
                    _refreshAll();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: isZh ? '刷新' : 'Refresh',
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
                          hintText: isZh ? _kAdbShellHintZh : _kAdbShellHintEn,
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
                  _DashboardActionButton(
                    onPressed: _runningShell ? null : _runShell,
                    icon: _runningShell
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 16),
                    label: isZh ? '执行' : 'Run',
                    filled: true,
                    height: _kAdbInlineControlHeight,
                  ),
                ],
              ),
              if (_shellHistory.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildShellHistoryChips(cs, theme, isZh),
              ],
              if (_shellOutputCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildShellOutputPanel(cs, theme, isZh),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShellHistoryChips(ColorScheme cs, ThemeData theme, bool isZh) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          isZh ? '最近' : 'Recent',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        for (final command in _shellHistory)
          ActionChip(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                command,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            tooltip: command,
            onPressed: () {
              setState(() {
                _shellCtrl.text = command;
                _shellCtrl.selection = TextSelection.collapsed(
                  offset: _shellCtrl.text.length,
                );
              });
            },
          ),
      ],
    );
  }

  Widget _buildShellOutputPanel(ColorScheme cs, ThemeData theme, bool isZh) {
    final output = _shellOutputCtrl.text;
    final result = _lastShellResult;
    return Container(
      constraints: const BoxConstraints(maxHeight: _kShellOutputMaxHeight),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isZh ? 'ADB Shell 输出' : 'ADB Shell output',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _DashboardIconActionButton(
                    tooltip: isZh ? '复制输出' : 'Copy output',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: output.trim().isEmpty
                        ? null
                        : () => _copyText(output),
                  ),
                  const SizedBox(width: _kDashboardTrailingActionGap),
                  _DashboardIconActionButton(
                    tooltip: isZh ? '清空输出' : 'Clear output',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      _lastShellResult = null;
                      _shellOutputCtrl.clear();
                    }),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.7)),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Align(
                alignment: Alignment.topLeft,
                child: result == null
                    ? _formattedTerminalText(output, cs)
                    : _buildAdbCommandResultView(result, cs, theme, isZh),
              ),
            ),
          ),
        ],
      ),
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
              _DashboardActionButton(
                onPressed: _runningDeviceAction ? null : _connectWirelessDevice,
                icon: const Icon(Icons.link_rounded),
                label: isZh ? '连接' : 'Connect',
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
                    onSubmitted: (_) => _addForward(),
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
                    onSubmitted: (_) => _addForward(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _DashboardActionButton(
                  onPressed: serial == null || _runningDeviceAction
                      ? null
                      : _addForward,
                  icon: const Icon(Icons.add_rounded),
                  label: isZh ? '添加' : 'Add',
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
                    removeTooltip: isZh ? '移除转发' : 'Remove forward',
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
            isZh ? '反向端口映射' : 'Reverse port mapping',
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
                    controller: _reverseDeviceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isZh ? '设备端口' : 'device port',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _addReverse(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: _kAdbInlineControlHeight,
                  child: TextField(
                    controller: _reverseHostCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isZh ? '主机端口' : 'host port',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _addReverse(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _DashboardActionButton(
                  onPressed: serial == null || _runningDeviceAction
                      ? null
                      : _addReverse,
                  icon: const Icon(Icons.add_link_rounded),
                  label: isZh ? '添加' : 'Add',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_reverseRows.isEmpty)
            Text(
              isZh ? '暂无反向映射' : 'No active reverse mappings',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in _reverseRows)
                  _ForwardRow(
                    row: row,
                    colorScheme: cs,
                    removeTooltip: isZh ? '移除反向映射' : 'Remove reverse mapping',
                    onRemove: _runningDeviceAction
                        ? null
                        : () => _removeReverseFromRow(row),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _runningDeviceAction
                        ? null
                        : () => _runDeviceAction(
                            () => _ctrl
                                .removeAllReverses(serial: serial)
                                .then(
                                  (ok) => AdbCommandResult(
                                    args: const <String>[
                                      'reverse',
                                      '--remove-all',
                                    ],
                                    exitCode: ok ? 0 : 1,
                                    stdout: ok ? 'removed all reverses' : '',
                                    stderr: ok ? '' : 'remove-all failed',
                                  ),
                                ),
                          ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    label: Text(isZh ? '移除全部反向映射' : 'Remove all reverses'),
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
            label: isZh ? '推送' : 'Push',
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
            label: isZh ? '拉取' : 'Pull',
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
                onPressed: serial == null || _runningDeviceAction
                    ? null
                    : () async {
                        final confirmed = await _confirmAction(
                          title: isZh ? '清空设备 Logcat？' : 'Clear device logcat?',
                          message: isZh
                              ? '将清空当前设备的 Logcat 缓冲区。'
                              : 'This clears the current device logcat buffer.',
                          confirmLabel: isZh ? '清空' : 'Clear',
                        );
                        if (!confirmed) return;
                        await _runDeviceAction(
                          () =>
                              _ctrl.clearLogcatDetailed(serial: _targetSerial),
                        );
                      },
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
              _SmallActionButton(
                icon: Icons.filter_center_focus_rounded,
                label: isZh ? '前台窗口' : 'Focus',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset(
                        'dumpsys window | grep -E "mCurrentFocus|mFocusedApp" | head -8',
                      ),
              ),
              _SmallActionButton(
                icon: Icons.sd_storage_rounded,
                label: isZh ? '存储' : 'Storage',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset(
                        'df -h /data /sdcard 2>/dev/null || df /data /sdcard',
                      ),
              ),
              _SmallActionButton(
                icon: Icons.tune_rounded,
                label: isZh ? '属性' : 'Props',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset(
                        'getprop | grep -E "ro.product|ro.build|ro.debuggable|ro.secure" | head -120',
                      ),
              ),
              _SmallActionButton(
                icon: Icons.light_mode_rounded,
                label: isZh ? '亮屏' : 'Wake',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('input keyevent KEYCODE_WAKEUP'),
              ),
              _SmallActionButton(
                icon: Icons.power_settings_new_rounded,
                label: isZh ? '电源键' : 'Power',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('input keyevent KEYCODE_POWER'),
              ),
              _SmallActionButton(
                icon: Icons.volume_up_rounded,
                label: isZh ? '音量+' : 'Vol+',
                onPressed: serial == null
                    ? null
                    : () => _runShellPreset('input keyevent KEYCODE_VOLUME_UP'),
              ),
              _SmallActionButton(
                icon: Icons.security_rounded,
                label: isZh ? '包权限' : 'Permissions',
                onPressed: serial == null || _logcatPackageTarget() == null
                    ? null
                    : () => _runShellPreset(
                        'dumpsys package ${_logcatPackageTarget()} | grep -Ei "requested permissions:|install permissions:|runtime permissions:|android.permission" | head -140',
                      ),
              ),
            ],
          ),
          if (_lastDeviceActionOutput != null &&
              _lastDeviceActionOutput!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _lastDeviceActionResult == null
                  ? _formattedTerminalText(_lastDeviceActionOutput!, cs)
                  : _buildAdbCommandResultView(
                      _lastDeviceActionResult!,
                      cs,
                      theme,
                      isZh,
                    ),
            ),
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
    final local = optionalIntFromValue(_forwardLocalCtrl.text);
    final remote = optionalIntFromValue(_forwardRemoteCtrl.text);
    if (!_isValidTcpPort(local) || !_isValidTcpPort(remote)) {
      _setDeviceActionMessage(
        zh: '端口转发失败：本地端口和设备端口必须在 $_kMinTcpPort-$_kMaxTcpPort 范围内。',
        en: 'Forward failed: local and device ports must be between $_kMinTcpPort and $_kMaxTcpPort.',
      );
      return;
    }
    await _runDeviceAction(
      () => _ctrl.forwardPortDetailed(local!, remote!, serial: _targetSerial),
    );
  }

  Future<void> _removeForwardFromRow(String row) async {
    final match = RegExp(r'tcp:(\d+)').firstMatch(row);
    final local = optionalIntFromValue(match?.group(1));
    if (local == null) return;
    await _runDeviceAction(
      () => _ctrl.removeForwardDetailed(local, serial: _targetSerial),
    );
  }

  Future<void> _addReverse() async {
    final devicePort = optionalIntFromValue(_reverseDeviceCtrl.text);
    final hostPort = optionalIntFromValue(_reverseHostCtrl.text);
    if (!_isValidTcpPort(devicePort) || !_isValidTcpPort(hostPort)) {
      _setDeviceActionMessage(
        zh: '反向映射失败：设备端口和主机端口必须在 $_kMinTcpPort-$_kMaxTcpPort 范围内。',
        en: 'Reverse mapping failed: device and host ports must be between $_kMinTcpPort and $_kMaxTcpPort.',
      );
      return;
    }
    await _runDeviceAction(
      () => _ctrl.reversePortDetailed(
        devicePort!,
        hostPort!,
        serial: _targetSerial,
      ),
    );
  }

  Future<void> _removeReverseFromRow(String row) async {
    final match = RegExp(r'tcp:(\d+)').firstMatch(row);
    final devicePort = int.tryParse(match?.group(1) ?? '');
    if (devicePort == null) return;
    await _runDeviceAction(
      () => _ctrl.removeReverseDetailed(devicePort, serial: _targetSerial),
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
            openHandIsChineseLocale(context) ? '查看端口映射' : 'List port mappings',
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

  bool _isValidTcpPort(int? port) =>
      port != null && port >= _kMinTcpPort && port <= _kMaxTcpPort;

  void _setDeviceActionMessage({required String zh, required String en}) {
    if (!mounted) return;
    setState(() {
      _lastDeviceActionResult = null;
      _lastDeviceActionOutput = openHandIsChineseLocale(context) ? zh : en;
    });
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
    return showOpenHandConfirmDialog(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: true,
    );
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
      (isZh ? '分析模式' : 'Analysis mode', _analysisModeLabel(config, isZh)),
      if (config.authorizationScope != null &&
          config.authorizationScope!.trim().isNotEmpty)
        (isZh ? '授权范围' : 'Authorization', config.authorizationScope!.trim()),
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
      ] else if (config.deviceSerial != null &&
          config.deviceSerial!.trim().isNotEmpty) ...[
        (isZh ? '配置设备' : 'Configured serial', config.deviceSerial!.trim()),
      ],
      if (config.keywords.isNotEmpty)
        (isZh ? '关键字' : 'Keywords', config.keywords.join(', ')),
      if (config.notes != null && config.notes!.isNotEmpty)
        (isZh ? '备注' : 'Notes', config.notes!),
    ];
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _dashboardSectionHeader(
            leading: const [],
            actions: [
              _DashboardActionButton(
                onPressed: _makingEvidenceBundle ? null : _makeEvidenceBundle,
                icon: _makingEvidenceBundle
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.inventory_2_rounded),
                label: isZh ? '生成证据包' : 'Make evidence bundle',
              ),
              if (_evidenceBundleOutput?.trim().isNotEmpty ?? false)
                _DashboardActionButton(
                  onPressed: () => _copyText(_evidenceBundleOutput!.trim()),
                  icon: const Icon(Icons.copy_rounded),
                  label: isZh ? '复制结果' : 'Copy result',
                ),
            ],
          ),
          if (_evidenceBundleOutput?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            _monospaceCard(cs, _evidenceBundleOutput!.trim()),
          ],
          const SizedBox(height: 12),
          for (final (label, value) in items)
            Padding(
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
            ),
        ],
      ),
    );
  }

  String _analysisModeLabel(AndroidReverseSessionConfig config, bool isZh) {
    if (isZh) return config.analysisMode.labelZh;
    return switch (config.analysisMode) {
      AndroidReverseAnalysisMode.staticFirst => 'Static first',
      AndroidReverseAnalysisMode.balanced => 'Balanced',
      AndroidReverseAnalysisMode.dynamicFirst => 'Dynamic first',
    };
  }

  // ── Toolchain tab ───────────────────────────────────────────────────────

  Widget _buildToolchainTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final pluginController = context.watch<PluginServiceController>();
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
          child: _dashboardSectionHeader(
            leading: [
              if (_toolchainRows.isNotEmpty)
                _StatusPill(
                  label: isZh
                      ? '必需缺失 $requiredMissing · 可选缺失 $optionalMissing'
                      : 'required missing $requiredMissing · optional missing $optionalMissing',
                  color: requiredMissing == 0 ? cs.primary : cs.error,
                ),
            ],
            actions: [
              _DashboardActionButton(
                onPressed: _loadingToolchain ? null : _refreshToolchain,
                icon: _loadingToolchain
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: isZh ? '刷新' : 'Refresh',
              ),
            ],
          ),
        ),
        if (_lastToolchainCommandResult != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.58),
                ),
              ),
              child: _buildAdbCommandResultView(
                _lastToolchainCommandResult!,
                cs,
                theme,
                isZh,
              ),
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
                      final plugin = _toolchainPluginForProbe(
                        row.probe,
                        pluginController,
                      );
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
                        title: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              row.probe.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (row.probe.required)
                              _StatusPill(
                                label: isZh ? '必需' : 'required',
                                color: cs.error,
                                compact: true,
                                subtle: true,
                              ),
                            if (plugin != null)
                              _StatusPill(
                                label: isZh ? '插件托管' : 'plugin-managed',
                                color: cs.secondary,
                                compact: true,
                                subtle: true,
                              ),
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
                            _DashboardIconActionButton(
                              icon: const Icon(Icons.copy_rounded),
                              tooltip: isZh ? '复制诊断' : 'Copy diagnostic',
                              onPressed: () => _copyText(
                                '${row.probe.label}\n${row.displayValue}\n${row.installHint(isZh)}',
                              ),
                            ),
                            const SizedBox(width: _kDashboardTrailingActionGap),
                            _DashboardPopupIconActionButton<
                              _ToolchainCommandAction
                            >(
                              tooltip: isZh
                                  ? '安装 / 更新 / 卸载 / 信息'
                                  : 'Install / update / uninstall / info',
                              icon: const Icon(Icons.terminal_rounded),
                              itemBuilder: (context) =>
                                  _toolchainCommandMenuItems(row.probe, isZh),
                              onSelected: (action) => _handleToolchainAction(
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

  // ── MCP tab ─────────────────────────────────────────────────────────────

  Widget _buildMcpTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final mcpController = context.watch<McpController>();
    final capabilities =
        TemplateRuntimeDependencyRegistry.androidReverse.mcpCapabilities;
    final serverRows = _androidMcpServerViews(mcpController);
    final configuredCapabilityCount = capabilities.where((capability) {
      return _matchingAndroidMcpServersForCapability(
        mcpController,
        capability,
      ).isNotEmpty;
    }).length;
    final totalAndroidTools = serverRows.fold<int>(
      0,
      (sum, row) => sum + row.matchedTools.length,
    );

    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        children: [
          _dashboardSectionHeader(
            leading: [
              _StatusPill(
                label: isZh
                    ? '$configuredCapabilityCount/${capabilities.length} 个能力 · $totalAndroidTools 个工具'
                    : '$configuredCapabilityCount/${capabilities.length} capabilities · $totalAndroidTools tools',
                color: cs.primary,
              ),
            ],
            actions: [
              _DashboardActionButton(
                onPressed: mcpController.isLoading
                    ? null
                    : () => unawaited(mcpController.refresh()),
                icon: mcpController.isLoading
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.sync_rounded),
                label: isZh ? '刷新 MCP' : 'Refresh MCP',
              ),
              _DashboardActionButton(
                onPressed: _writingMcpArtifacts
                    ? null
                    : _ensureMcpLinkageArtifacts,
                icon: _writingMcpArtifacts
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.article_rounded),
                label: isZh ? '生成联动工件' : 'Generate artifacts',
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
            isZh ? '推荐 MCP 能力' : 'Recommended MCP capabilities',
          ),
          const SizedBox(height: 8),
          for (final capability in capabilities) ...[
            _buildAndroidMcpCapabilityCard(
              capability,
              mcpController,
              cs,
              theme,
              isZh,
            ),
            const SizedBox(height: 8),
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
        ],
      ),
    );
  }

  // ── Plugins tab ────────────────────────────────────────────────────────

  Widget _buildPluginsTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final pluginController = context.watch<PluginServiceController>();
    final runtimePlugins = _kAndroidRuntimePluginIds
        .map(pluginController.pluginById)
        .whereType<PluginInfo>()
        .toList(growable: false);
    final installedRuntimeCount = runtimePlugins
        .where((plugin) => plugin.isInstalled)
        .length;

    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        children: [
          _dashboardSectionHeader(
            leading: [
              _StatusPill(
                label: isZh
                    ? '$installedRuntimeCount/${runtimePlugins.length} 个前置条件可用'
                    : '$installedRuntimeCount/${runtimePlugins.length} prerequisites ready',
                color: installedRuntimeCount == runtimePlugins.length
                    ? cs.primary
                    : cs.tertiary,
              ),
            ],
            actions: [
              _DashboardActionButton(
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
                    : const Icon(Icons.refresh_rounded),
                label: isZh ? '扫描插件' : 'Scan plugins',
              ),
              _DashboardActionButton(
                onPressed: _loadingToolchain ? null : _refreshToolchain,
                icon: _loadingToolchain
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.construction_rounded),
                label: isZh ? '刷新工具链' : 'Refresh tools',
              ),
            ],
          ),
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
                        ? '插件服务暂未返回 Android 逆向关联插件状态。'
                        : 'Plugin service has not reported Android reverse plugin status.'),
            )
          else
            for (final plugin in runtimePlugins) ...[
              _buildRuntimePluginTile(
                plugin,
                pluginController,
                cs,
                theme,
                isZh,
              ),
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
          else if (_toolchainRows.isNotEmpty)
            for (final row in _toolchainRows) ...[
              _buildToolchainCommandTile(row, cs, theme, isZh),
              const SizedBox(height: 8),
            ],
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
              Wrap(
                spacing: _kDashboardTrailingActionGap,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  _DashboardIconActionButton(
                    tooltip: server.enabled
                        ? (isZh ? '禁用 MCP' : 'Disable MCP')
                        : (isZh ? '启用 MCP' : 'Enable MCP'),
                    icon: Icon(
                      server.enabled
                          ? Icons.toggle_on_rounded
                          : Icons.toggle_off_outlined,
                    ),
                    onPressed: () => unawaited(
                      _toggleAndroidMcpServer(server, !server.enabled, isZh),
                    ),
                  ),
                  _DashboardIconActionButton(
                    tooltip: isZh ? '检查健康状态' : 'Check health',
                    icon: health.status == McpServerHealthStatus.checking
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 1.7),
                          )
                        : const Icon(Icons.health_and_safety_rounded),
                    onPressed: health.status == McpServerHealthStatus.checking
                        ? null
                        : () => unawaited(
                            context.read<McpController>().checkServerHealth(
                              server.name,
                            ),
                          ),
                  ),
                  _DashboardIconActionButton(
                    tooltip: isZh ? '刷新此 MCP 工具目录' : 'Refresh this MCP catalog',
                    icon: catalog.isLoading
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 1.7),
                          )
                        : const Icon(Icons.sync_rounded),
                    onPressed: catalog.isLoading
                        ? null
                        : () => unawaited(
                            context.read<McpController>().refreshServerTools(
                              server.name,
                            ),
                          ),
                  ),
                  if (query != null)
                    _DashboardIconActionButton(
                      tooltip: isZh
                          ? '复制 ToolSearch 查询'
                          : 'Copy ToolSearch query',
                      icon: const Icon(Icons.manage_search_rounded),
                      onPressed: () => _copyText(query),
                    ),
                  _DashboardIconActionButton(
                    tooltip: isZh ? '删除 MCP 服务' : 'Delete MCP service',
                    icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                    onPressed: () =>
                        unawaited(_deleteAndroidMcpServer(server, isZh)),
                  ),
                ],
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

  Widget _buildAndroidMcpCapabilityCard(
    TemplateRuntimeMcpCapabilitySpec capability,
    McpController controller,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    final matches = _matchingAndroidMcpServersForCapability(
      controller,
      capability,
    );
    final installed = matches.isNotEmpty;
    final canInstall = _canRegisterAndroidMcpCapability(capability);
    final statusColor = installed
        ? cs.primary
        : canInstall
        ? cs.tertiary
        : cs.outline;
    final statusLabel = installed
        ? (isZh ? '已配置 ${matches.length}' : '${matches.length} configured')
        : canInstall
        ? (isZh ? '可安装' : 'installable')
        : (isZh ? '缺少安装源' : 'source missing');
    final firstServer = matches.isEmpty ? null : matches.first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.62)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            installed
                ? Icons.extension_rounded
                : Icons.add_circle_outline_rounded,
            size: 19,
            color: statusColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      isZh ? capability.labelZh : capability.labelEn,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    _StatusPill(label: statusLabel, color: statusColor),
                    if (capability.packageName?.trim().isNotEmpty ?? false)
                      _StatusPill(
                        label: capability.packageName!.trim(),
                        color: cs.secondary,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    isZh ? capability.descriptionZh : capability.descriptionEn,
                    if (firstServer != null)
                      '${isZh ? "服务" : "server"}: ${firstServer.name}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Wrap(
            spacing: _kDashboardTrailingActionGap,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              _DashboardActionButton(
                onPressed: installed || !canInstall || controller.isLoading
                    ? null
                    : () => unawaited(
                        _installAndroidMcpCapability(capability, isZh),
                      ),
                icon: const Icon(Icons.download_rounded),
                label: isZh ? '安装' : 'Install',
              ),
              _DashboardActionButton(
                onPressed: !installed || controller.isLoading
                    ? null
                    : () => unawaited(
                        _refreshAndroidMcpCapability(matches, isZh),
                      ),
                icon: const Icon(Icons.system_update_alt_rounded),
                label: isZh ? '更新' : 'Update',
              ),
              _DashboardActionButton(
                onPressed: !installed || controller.isLoading
                    ? null
                    : () => unawaited(
                        _uninstallAndroidMcpCapability(
                          capability,
                          matches,
                          isZh,
                        ),
                      ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: isZh ? '卸载' : 'Uninstall',
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _canRegisterAndroidMcpCapability(
    TemplateRuntimeMcpCapabilitySpec capability,
  ) {
    final name = capability.suggestedServerName?.trim();
    final command = capability.suggestedCommand?.trim();
    final url = capability.suggestedUrl?.trim();
    if (name == null || name.isEmpty) return false;
    if ((command == null || command.isEmpty) && (url == null || url.isEmpty)) {
      return false;
    }
    return !_hasMcpCapabilityPlaceholder(capability);
  }

  bool _hasMcpCapabilityPlaceholder(
    TemplateRuntimeMcpCapabilitySpec capability,
  ) {
    bool hasPlaceholder(String? value) =>
        value != null && (value.contains('<') || value.contains('>'));
    return hasPlaceholder(capability.suggestedCommand) ||
        hasPlaceholder(capability.suggestedUrl) ||
        capability.suggestedArgs.any(hasPlaceholder);
  }

  Future<void> _installAndroidMcpCapability(
    TemplateRuntimeMcpCapabilitySpec capability,
    bool isZh,
  ) async {
    if (!_canRegisterAndroidMcpCapability(capability)) {
      _showSnack(
        isZh ? '该 MCP 缺少可直接安装的来源。' : 'This MCP has no direct install source.',
      );
      return;
    }
    final server = McpServer(
      name: capability.suggestedServerName!.trim(),
      type: (capability.suggestedUrl?.trim().isNotEmpty ?? false)
          ? McpServerType.sse
          : McpServerType.stdio,
      enabled: true,
      url: capability.suggestedUrl?.trim() ?? '',
      command: capability.suggestedCommand?.trim() ?? '',
      args: capability.suggestedArgs,
    );
    final ok = await context.read<McpController>().saveServer(server);
    if (!mounted) return;
    _showSnack(
      ok
          ? (isZh ? '已安装 MCP：${server.name}' : 'MCP installed: ${server.name}')
          : (isZh
                ? 'MCP 已存在或名称冲突：${server.name}'
                : 'MCP exists or name conflicts: ${server.name}'),
    );
    if (ok) {
      unawaited(context.read<McpController>().reconnectServer(server.name));
    }
  }

  Future<void> _refreshAndroidMcpCapability(
    List<McpServer> servers,
    bool isZh,
  ) async {
    if (servers.isEmpty) return;
    final controller = context.read<McpController>();
    await Future.wait<void>(
      servers.map((server) => controller.reconnectServer(server.name)),
    );
    if (!mounted) return;
    _showSnack(isZh ? '已更新 MCP 状态。' : 'MCP status updated.');
  }

  Future<void> _uninstallAndroidMcpCapability(
    TemplateRuntimeMcpCapabilitySpec capability,
    List<McpServer> servers,
    bool isZh,
  ) async {
    if (servers.isEmpty) return;
    final names = servers.map((server) => server.name).join(', ');
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '卸载 MCP 能力？' : 'Uninstall MCP capability?',
      message: isZh
          ? '将从 OpenHand MCP 配置中删除 ${isZh ? capability.labelZh : capability.labelEn} 对应服务：$names。'
          : 'This removes the servers for ${capability.labelEn} from the OpenHand MCP configuration: $names.',
      cancelLabel: isZh ? '取消' : 'Cancel',
      confirmLabel: isZh ? '卸载' : 'Uninstall',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final controller = context.read<McpController>();
    var ok = true;
    for (final server in servers) {
      ok = await controller.deleteServer(server) && ok;
    }
    if (!mounted) return;
    _showSnack(
      ok
          ? (isZh ? '已卸载 MCP：$names' : 'MCP uninstalled: $names')
          : (isZh ? '卸载 MCP 失败：$names' : 'Failed to uninstall MCP: $names'),
    );
  }

  Future<void> _toggleAndroidMcpServer(
    McpServer server,
    bool enabled,
    bool isZh,
  ) async {
    final ok = await context.read<McpController>().updateServerEnabled(
      server.name,
      enabled,
    );
    if (!mounted) return;
    _showSnack(
      ok
          ? enabled
                ? (isZh
                      ? '已启用 MCP：${server.name}'
                      : 'MCP enabled: ${server.name}')
                : (isZh
                      ? '已禁用 MCP：${server.name}'
                      : 'MCP disabled: ${server.name}')
          : (isZh ? 'MCP 状态更新失败' : 'Failed to update MCP status'),
    );
  }

  Future<void> _deleteAndroidMcpServer(McpServer server, bool isZh) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '删除 MCP 服务？' : 'Delete MCP service?',
      message: isZh
          ? '将从 OpenHand MCP 配置中删除 ${server.name}。'
          : 'This will remove ${server.name} from the OpenHand MCP configuration.',
      cancelLabel: isZh ? '取消' : 'Cancel',
      confirmLabel: isZh ? '删除' : 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await context.read<McpController>().deleteServer(server);
    if (!mounted) return;
    _showSnack(
      ok
          ? (isZh ? '已删除 MCP：${server.name}' : 'MCP deleted: ${server.name}')
          : (isZh ? '删除 MCP 失败' : 'Failed to delete MCP'),
    );
  }

  Widget _buildRuntimePluginTile(
    PluginInfo plugin,
    PluginServiceController pluginController,
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
    final actions = _runtimePluginActions(plugin);
    final actionBusy =
        plugin.isBusy ||
        pluginController.isOperating ||
        pluginController.checkingPluginId == plugin.id;
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
            const SizedBox(width: _kDashboardTrailingActionGap),
            _DashboardIconActionButton(
              tooltip: isZh ? '复制路径' : 'Copy path',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => _copyText(path),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(width: _kDashboardTrailingActionGap),
            _DashboardPopupIconActionButton<_RuntimePluginAction>(
              tooltip: isZh ? '插件操作' : 'Plugin actions',
              icon: const Icon(Icons.more_horiz_rounded, size: 17),
              itemBuilder: (context) => actions
                  .map(
                    (action) => PopupMenuItem<_RuntimePluginAction>(
                      value: action,
                      enabled:
                          action == _RuntimePluginAction.info || !actionBusy,
                      child: Row(
                        children: [
                          Icon(_runtimePluginActionIcon(action), size: 16),
                          const SizedBox(width: 8),
                          Text(_runtimePluginActionLabel(action, isZh)),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
              onSelected: (action) =>
                  unawaited(_handleRuntimePluginAction(plugin, action, isZh)),
            ),
          ],
        ],
      ),
    );
  }

  List<_RuntimePluginAction> _runtimePluginActions(PluginInfo plugin) {
    if (plugin.isBusy) {
      return const <_RuntimePluginAction>[_RuntimePluginAction.info];
    }
    if (plugin.isInstalled) {
      return <_RuntimePluginAction>[
        _RuntimePluginAction.info,
        _RuntimePluginAction.checkUpdate,
        if (plugin.hasUpdate || _kAndroidRuntimePluginIds.contains(plugin.id))
          _RuntimePluginAction.update,
        plugin.enabled
            ? _RuntimePluginAction.disable
            : _RuntimePluginAction.enable,
        if (plugin.supportsUninstall) _RuntimePluginAction.uninstall,
      ];
    }
    return const <_RuntimePluginAction>[
      _RuntimePluginAction.info,
      _RuntimePluginAction.install,
    ];
  }

  IconData _runtimePluginActionIcon(_RuntimePluginAction action) {
    return switch (action) {
      _RuntimePluginAction.info => Icons.info_outline_rounded,
      _RuntimePluginAction.install => Icons.download_rounded,
      _RuntimePluginAction.checkUpdate => Icons.refresh_rounded,
      _RuntimePluginAction.update => Icons.system_update_alt_rounded,
      _RuntimePluginAction.enable => Icons.toggle_on_rounded,
      _RuntimePluginAction.disable => Icons.toggle_off_outlined,
      _RuntimePluginAction.uninstall => Icons.delete_outline_rounded,
    };
  }

  String _runtimePluginActionLabel(_RuntimePluginAction action, bool isZh) {
    return switch (action) {
      _RuntimePluginAction.info => isZh ? '查看信息' : 'View info',
      _RuntimePluginAction.install => isZh ? '安装' : 'Install',
      _RuntimePluginAction.checkUpdate => isZh ? '检查更新' : 'Check updates',
      _RuntimePluginAction.update => isZh ? '更新' : 'Update',
      _RuntimePluginAction.enable => isZh ? '启用' : 'Enable',
      _RuntimePluginAction.disable => isZh ? '禁用' : 'Disable',
      _RuntimePluginAction.uninstall => isZh ? '卸载' : 'Uninstall',
    };
  }

  void _showRuntimePluginInfoDialog(PluginInfo plugin, bool isZh) {
    showAndroidReverseToolDialog<void>(
      context: context,
      builder: (_) => _RuntimePluginInfoDialog(plugin: plugin, isZh: isZh),
    );
  }

  Future<void> _handleRuntimePluginAction(
    PluginInfo plugin,
    _RuntimePluginAction action,
    bool isZh,
  ) async {
    final pluginController = context.read<PluginServiceController>();
    switch (action) {
      case _RuntimePluginAction.info:
        _showRuntimePluginInfoDialog(plugin, isZh);
        return;
      case _RuntimePluginAction.enable:
      case _RuntimePluginAction.disable:
        pluginController.toggleEnabled(
          plugin.id,
          enabled: action == _RuntimePluginAction.enable,
        );
        _showSnack(
          action == _RuntimePluginAction.enable
              ? (isZh ? '已启用 ${plugin.name}' : '${plugin.name} enabled')
              : (isZh ? '已禁用 ${plugin.name}' : '${plugin.name} disabled'),
        );
        return;
      case _RuntimePluginAction.checkUpdate:
        final refreshed = await pluginController.checkPluginUpdate(plugin.id);
        if (!mounted) return;
        final latest = pluginController.pluginById(plugin.id) ?? refreshed;
        _showSnack(
          latest == null
              ? (pluginController.errorMessage ??
                    (isZh ? '检查更新失败' : 'Failed to check updates'))
              : latest.hasUpdate && latest.latestVersion != null
              ? (isZh
                    ? '发现新版本：${latest.latestVersion}'
                    : 'New version available: ${latest.latestVersion}')
              : (isZh ? '未发现新版本' : 'No updates available'),
        );
        return;
      case _RuntimePluginAction.install:
      case _RuntimePluginAction.update:
      case _RuntimePluginAction.uninstall:
        await _runRuntimePluginMutation(plugin, action, isZh);
    }
  }

  Future<void> _runRuntimePluginMutation(
    PluginInfo plugin,
    _RuntimePluginAction action,
    bool isZh,
  ) async {
    final title = switch (action) {
      _RuntimePluginAction.install =>
        isZh ? '安装 ${plugin.name}？' : 'Install ${plugin.name}?',
      _RuntimePluginAction.update =>
        isZh ? '更新 ${plugin.name}？' : 'Update ${plugin.name}?',
      _RuntimePluginAction.uninstall =>
        isZh ? '卸载 ${plugin.name}？' : 'Uninstall ${plugin.name}?',
      _ => '',
    };
    final message = switch (action) {
      _RuntimePluginAction.install =>
        isZh
            ? '将通过 OpenHand 插件服务安装 ${plugin.name}。安装可能需要下载依赖文件。'
            : 'OpenHand plugin service will install ${plugin.name}. Dependencies may be downloaded.',
      _RuntimePluginAction.update =>
        isZh
            ? '将通过 OpenHand 插件服务更新 ${plugin.name}。'
            : 'OpenHand plugin service will update ${plugin.name}.',
      _RuntimePluginAction.uninstall =>
        isZh
            ? '将从本机卸载 ${plugin.name}。此操作可能影响依赖它的能力。'
            : 'This will remove ${plugin.name} from this machine and may affect dependent capabilities.',
      _ => '',
    };
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: title,
      message: message,
      cancelLabel: isZh ? '取消' : 'Cancel',
      confirmLabel: _runtimePluginActionLabel(action, isZh),
      destructive: action == _RuntimePluginAction.uninstall,
    );
    if (!confirmed || !mounted) return;

    final pluginController = context.read<PluginServiceController>();
    final success = switch (action) {
      _RuntimePluginAction.install => await pluginController.installPlugin(
        plugin.id,
      ),
      _RuntimePluginAction.update => await pluginController.updatePlugin(
        plugin.id,
      ),
      _RuntimePluginAction.uninstall => await pluginController.uninstallPlugin(
        plugin.id,
      ),
      _ => false,
    };
    if (!mounted) return;
    _showSnack(
      success
          ? switch (action) {
              _RuntimePluginAction.install =>
                isZh ? '${plugin.name} 安装成功' : '${plugin.name} installed',
              _RuntimePluginAction.update =>
                isZh ? '${plugin.name} 更新成功' : '${plugin.name} updated',
              _RuntimePluginAction.uninstall =>
                isZh ? '${plugin.name} 卸载成功' : '${plugin.name} uninstalled',
              _ => plugin.name,
            }
          : (pluginController.errorMessage ??
                switch (action) {
                  _RuntimePluginAction.install =>
                    isZh
                        ? '${plugin.name} 安装失败'
                        : '${plugin.name} install failed',
                  _RuntimePluginAction.update =>
                    isZh
                        ? '${plugin.name} 更新失败'
                        : '${plugin.name} update failed',
                  _RuntimePluginAction.uninstall =>
                    isZh
                        ? '${plugin.name} 卸载失败'
                        : '${plugin.name} uninstall failed',
                  _ => plugin.name,
                }),
    );
  }

  void _showSnack(
    String message, {
    OpenHandSnackKind kind = OpenHandSnackKind.info,
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!mounted || message.trim().isEmpty) return;
    OpenHandSnackBar.flash(context, message, kind: kind, duration: duration);
  }

  Future<String?> _saveTextWithPicker({
    required String suggestedName,
    required String typeLabel,
    required List<String> extensions,
    required String content,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: typeLabel, extensions: extensions),
      ],
    );
    if (location == null) return null;
    await File(location.path).writeAsString(content, flush: true);
    return location.path;
  }

  String _fileTimestamp() {
    return DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll(RegExp(r'\.\d+'), '');
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
                compact: true,
                subtle: true,
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
          _dashboardActionWrap([
            for (final action in _toolchainVisibleActions(row.probe))
              _SmallActionButton(
                icon: _toolchainCommandIcon(action),
                label: _toolchainCommandLabel(action, isZh),
                onPressed: _isToolchainCommandRunning(row.probe, action)
                    ? null
                    : () => _handleToolchainAction(row.probe, action, isZh),
              ),
          ]),
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
          child: _dashboardSectionHeader(
            leading: [
              _StatusPill(
                label: isZh
                    ? '${_packages.length} 个 APP'
                    : '${_packages.length} apps',
                color: cs.primary,
              ),
            ],
            actions: [
              _DashboardActionButton(
                onPressed: _loadingPackages ? null : _doRefreshPackages,
                icon: _loadingPackages
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: isZh ? '刷新' : 'Refresh',
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
                                        _showSnack(
                                          isZh
                                              ? '已发送强制停止：$pkg'
                                              : 'Force-stop sent: $pkg',
                                          kind: OpenHandSnackKind.success,
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
              _DashboardActionButton(
                onPressed: _loadingProcesses ? null : _doRefreshProcesses,
                icon: _loadingProcesses
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: isZh ? '刷新' : 'Refresh',
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

  Widget _buildLogcatPackageFilterChip(
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    final packageName = _logcatPackageTarget()?.trim();
    if (packageName == null || packageName.isEmpty) {
      return const SizedBox.shrink();
    }
    final selected = _logcatPackageFilterEnabled;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    return Tooltip(
      message: isZh ? '按包名过滤 Logcat' : 'Filter logcat by package',
      child: FilterChip(
        selected: selected,
        avatar: Icon(Icons.apps_rounded, size: 15, color: color),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            packageName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        onSelected: (value) {
          setState(() {
            _logcatPackageFilterEnabled = value;
            if (value) _logcatPidCtrl.clear();
          });
          unawaited(_fetchLogcat());
        },
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget? _clearFieldSuffix({
    required ColorScheme cs,
    required bool visible,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    if (!visible) return null;
    return Tooltip(
      message: tooltip,
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: IconButton(
            onPressed: onPressed,
            icon: const Icon(Icons.close_rounded, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            splashRadius: 14,
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: cs.onSurfaceVariant,
              hoverColor: cs.primary.withValues(alpha: 0.08),
              focusColor: cs.primary.withValues(alpha: 0.08),
              highlightColor: cs.primary.withValues(alpha: 0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogcatTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dashboardSectionHeader(
                leading: [
                  _StatusPill(
                    label: '${_logcatLines.length}/$_logcatCacheLimit',
                    color: cs.primary,
                  ),
                  if (_logcatPackageTarget()?.isNotEmpty ?? false)
                    _buildLogcatPackageFilterChip(cs, theme, isZh),
                  if (_loadingLogcat)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                ],
                actions: [
                  _DashboardActionButton(
                    onPressed: _loadingLogcat ? null : _fetchLogcat,
                    icon: const Icon(Icons.refresh_rounded),
                    label: isZh ? '刷新' : 'Refresh',
                  ),
                  _DashboardActionButton(
                    onPressed: () => _setLogcatAutoRefresh(!_logcatAutoRefresh),
                    icon: Icon(
                      _logcatAutoRefresh
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                    label: _logcatAutoRefresh
                        ? (isZh ? '停止自动' : 'Stop auto')
                        : (isZh ? '自动刷新' : 'Auto refresh'),
                    filled: _logcatAutoRefresh,
                  ),
                  _DashboardActionButton(
                    onPressed: _capturingLogcatSnapshot
                        ? null
                        : _captureLogcatArtifactSnapshot,
                    icon: _capturingLogcatSnapshot
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.6),
                          )
                        : const Icon(Icons.snippet_folder_rounded),
                    label: isZh ? '快照' : 'Snapshot',
                  ),
                  _DashboardActionButton(
                    onPressed: _logcatLines.isEmpty || _savingLogcatFile
                        ? null
                        : _saveLogcatSnapshot,
                    icon: _savingLogcatFile
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.6),
                          )
                        : const Icon(Icons.save_alt_rounded),
                    label: isZh ? '保存' : 'Save',
                  ),
                  _DashboardActionButton(
                    onPressed: _logcatLines.isEmpty
                        ? null
                        : () => _copyText(_logcatLines.join('\n')),
                    icon: const Icon(Icons.copy_rounded),
                    label: isZh ? '复制' : 'Copy',
                  ),
                  _DashboardActionButton(
                    onPressed: _clearingLogcat ? null : _clearLogcat,
                    icon: _clearingLogcat
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.6),
                          )
                        : const Icon(Icons.delete_sweep_rounded),
                    label: isZh ? '清空' : 'Clear',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _dashboardActionWrap([
                SizedBox(
                  width: 220,
                  height: _kDashboardFilterControlHeight,
                  child: TextField(
                    controller: _logcatFilterCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isZh ? 'Tag 过滤' : 'Tag filter',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      suffixIcon: _clearFieldSuffix(
                        cs: cs,
                        visible: _logcatFilterCtrl.text.trim().isNotEmpty,
                        tooltip: isZh ? '清空过滤' : 'Clear filter',
                        onPressed: () {
                          setState(() => _logcatFilterCtrl.clear());
                          _fetchLogcat();
                        },
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _fetchLogcat(),
                  ),
                ),
                SizedBox(
                  width: isZh ? 118 : 126,
                  height: _kDashboardFilterControlHeight,
                  child: DropdownButtonFormField<String>(
                    initialValue: _logcatLevel,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: isZh ? '等级' : 'Level',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    items: [
                      for (final level in _kLogcatLevels)
                        DropdownMenuItem<String>(
                          value: level,
                          child: Text(_logcatLevelOptionLabel(level, isZh)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _logcatLevel = value);
                    },
                  ),
                ),
                SizedBox(
                  width: isZh ? 112 : 126,
                  height: _kDashboardFilterControlHeight,
                  child: DropdownButtonFormField<int>(
                    initialValue: _logcatCacheLimit,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: isZh ? '缓存' : 'Cache',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    items: const <int>[100, 200, 500, 1000, 2000]
                        .map(
                          (value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _logcatCacheLimit = value
                            .clamp(_kMinLogcatCacheLimit, _kMaxLogcatCacheLimit)
                            .toInt();
                        final retained = _trimLogcatBuffer(
                          List<String>.from(_logcatLines),
                        );
                        _logcatLines
                          ..clear()
                          ..addAll(retained);
                        _compactLogcatParseCache();
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 132,
                  height: _kDashboardFilterControlHeight,
                  child: TextField(
                    controller: _logcatPidCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'PID',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      suffixIcon: _clearFieldSuffix(
                        cs: cs,
                        visible: _logcatPidCtrl.text.trim().isNotEmpty,
                        tooltip: isZh ? '清空 PID' : 'Clear PID',
                        onPressed: () {
                          setState(() => _logcatPidCtrl.clear());
                          _fetchLogcat();
                        },
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _fetchLogcat(),
                  ),
                ),
              ]),
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
                      _DashboardActionButton(
                        onPressed: _loadingLogcat ? null : _fetchLogcat,
                        icon: const Icon(Icons.download_rounded),
                        label: isZh ? '加载 Logcat' : 'Load logcat',
                      ),
                    ],
                  ),
                )
              : OpenHandSafeScrollbar(
                  child: ListView.builder(
                    controller: _logcatScrollController,
                    cacheExtent: 520,
                    addAutomaticKeepAlives: false,
                    addSemanticIndexes: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: _logcatLines.length,
                    itemBuilder: (_, i) {
                      final line = _logcatLines[i];
                      return _LogcatLineTile(
                        parsed: _parseCachedLogcatLine(line),
                        colorScheme: cs,
                        theme: theme,
                        isZh: isZh,
                        onMenu: (position) =>
                            _showLogcatLineMenu(i, line, position, isZh),
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
                SizedBox(height: 150, child: snippets),
                const SizedBox(height: 10),
                Expanded(child: editor),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
    final selectedAssetLabel = Text(
      scriptAsset ?? (isZh ? '未选择内置 snippet' : 'No built-in snippet selected'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: cs.onSurfaceVariant,
        fontFamily: scriptAsset == null ? null : 'monospace',
      ),
    );
    final actions = <Widget>[
      _DashboardActionButton(
        onPressed: _fridaScriptCtrl.text.trim().isEmpty || _savingFridaScript
            ? null
            : _saveFridaScriptArtifact,
        icon: _savingFridaScript
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            : const Icon(Icons.save_alt_rounded),
        label: isZh ? '保存工件' : 'Save artifact',
      ),
      _DashboardActionButton(
        onPressed: _fridaScriptCtrl.text.trim().isEmpty
            ? null
            : () => _copyText(_fridaScriptCtrl.text),
        icon: const Icon(Icons.copy_rounded),
        label: isZh ? '复制脚本' : 'Copy script',
      ),
      _DashboardActionButton(
        onPressed: _runningFridaDoctor || _runningFridaAction
            ? null
            : _runFridaDoctor,
        icon: _runningFridaDoctor
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            : const Icon(Icons.health_and_safety_rounded),
        label: isZh ? '运行诊断' : 'Run doctor',
      ),
      _DashboardActionButton(
        onPressed: _runningFridaAction ? null : _readFridaArtifacts,
        icon: _runningFridaAction
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            : const Icon(Icons.folder_open_rounded),
        label: isZh ? '读取工件' : 'Read artifacts',
      ),
      _DashboardActionButton(
        onPressed: _runningFridaAction ? null : _startExistingFridaServer,
        icon: _runningFridaAction
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            : const Icon(Icons.play_circle_outline_rounded),
        label: isZh ? '启动服务' : 'Start server',
      ),
      _DashboardActionButton(
        onPressed: _runningFridaAction || _fridaScriptCtrl.text.trim().isEmpty
            ? null
            : () => _runFridaCapture(spawn: true),
        icon: const Icon(Icons.rocket_launch_rounded),
        label: isZh ? 'Spawn 注入' : 'Spawn',
      ),
      _DashboardActionButton(
        onPressed: _runningFridaAction || _fridaScriptCtrl.text.trim().isEmpty
            ? null
            : () => _runFridaCapture(spawn: false),
        icon: const Icon(Icons.link_rounded),
        label: isZh ? 'Attach 注入' : 'Attach',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TextField(
            controller: _fridaScriptCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              hintText: isZh
                  ? '// 选择 snippet 或粘贴脚本...'
                  : '// Load a snippet or paste script...',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  selectedAssetLabel,
                  const SizedBox(height: 8),
                  _dashboardActionWrap(actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: selectedAssetLabel),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _dashboardActionWrap(actions)),
              ],
            );
          },
        ),
        if (_fridaArtifactOutput?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: OpenHandSafeScrollbar(
              child: ListView(
                children: [_monospaceCard(cs, _fridaArtifactOutput!.trim())],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Network tab ─────────────────────────────────────────────────────────

  Widget _buildNetworkTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final addonOutput = _networkAddonOutput?.trim();
    final captureRunning = _ctrl.networkCaptureRunning;
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _dashboardSectionHeader(
            leading: [
              _StatusPill(
                label: captureRunning
                    ? (isZh
                          ? '抓包中 PID ${_ctrl.networkCapturePid}'
                          : 'capturing PID ${_ctrl.networkCapturePid}')
                    : (isZh ? '未抓包' : 'idle'),
                color: captureRunning ? cs.primary : cs.outline,
              ),
            ],
            actions: [
              _DashboardActionButton(
                onPressed: _writingNetworkAddon ? null : _ensureMitmproxyAddon,
                icon: _writingNetworkAddon
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.receipt_long_rounded),
                label: isZh ? '生成 JSONL Addon' : 'Generate JSONL addon',
              ),
              _DashboardActionButton(
                onPressed: _runningNetworkProbe || _runningNetworkAction
                    ? null
                    : _runNetworkProxyProbe,
                icon: _runningNetworkProbe
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.fact_check_rounded),
                label: isZh ? '运行预检' : 'Run preflight',
              ),
              if (addonOutput != null && addonOutput.isNotEmpty)
                _DashboardActionButton(
                  onPressed: () => _copyText(addonOutput),
                  icon: const Icon(Icons.copy_rounded),
                  label: isZh ? '复制结果' : 'Copy result',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _pathTextField(
                  controller: _networkProxyHostCtrl,
                  hintText: isZh
                      ? '代理主机，例如 10.0.2.2'
                      : 'Proxy host, e.g. 10.0.2.2',
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: _pathTextField(
                  controller: _networkProxyPortCtrl,
                  hintText: isZh ? '端口' : 'Port',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _dashboardActionWrap([
            _DashboardActionButton(
              onPressed: _runningNetworkAction || captureRunning
                  ? null
                  : _startNetworkCapture,
              icon: _runningNetworkAction
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
                    )
                  : const Icon(Icons.fiber_manual_record_rounded),
              label: isZh ? '启动抓包' : 'Start capture',
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction || !captureRunning
                  ? null
                  : () => _runNetworkAction(_ctrl.stopNetworkCapture),
              icon: const Icon(Icons.stop_circle_rounded),
              label: isZh ? '停止抓包' : 'Stop capture',
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction ? null : _setDeviceProxy,
              icon: const Icon(Icons.settings_ethernet_rounded),
              label: isZh ? '设置代理' : 'Set proxy',
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction ? null : _readDeviceProxy,
              icon: const Icon(Icons.visibility_rounded),
              label: isZh ? '读取代理' : 'Read proxy',
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction ? null : _clearDeviceProxy,
              icon: const Icon(Icons.cleaning_services_rounded),
              label: isZh ? '清除代理' : 'Clear proxy',
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction
                  ? null
                  : () => _runNetworkAction(_ctrl.readNetworkCaptureSummary),
              icon: const Icon(Icons.article_rounded),
              label: isZh ? '读取抓包' : 'Read capture',
            ),
            _DashboardActionButton(
              onPressed: _runningNetworkAction
                  ? null
                  : _exportNetworkFlowsWithPicker,
              icon: const Icon(Icons.ios_share_rounded),
              label: isZh ? '导出 flows' : 'Export flows',
            ),
          ]),
          const SizedBox(height: 10),
          if (addonOutput != null && addonOutput.isNotEmpty)
            _monospaceCard(cs, addonOutput),
        ],
      ),
    );
  }

  // ── Static analysis tab ─────────────────────────────────────────────────

  Widget _buildStaticTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final scanOutput = _staticQuickScanOutput?.trim();
    final staticBusy = _runningStaticQuickScan || _runningStaticAction;
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _dashboardSectionHeader(
            leading: const [],
            actions: [
              _DashboardActionButton(
                onPressed: staticBusy ? null : _runStaticQuickScan,
                icon: _runningStaticQuickScan
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.manage_search_rounded),
                label: isZh ? '快速扫描 APK' : 'Quick scan APK',
              ),
              _DashboardActionButton(
                onPressed: staticBusy
                    ? null
                    : () => _runStaticAction(
                        () => _ctrl.readStaticQuickScanArtifacts(
                          apkPath: _ctrl.config.apkPath,
                          packageName: _logcatPackageTarget(),
                        ),
                      ),
                icon: const Icon(Icons.folder_open_rounded),
                label: isZh ? '读取产物' : 'Read artifacts',
              ),
              _DashboardActionButton(
                onPressed: staticBusy
                    ? null
                    : () => _runStaticAction(
                        () => _ctrl.inspectApkIdentity(
                          apkPath: _ctrl.config.apkPath,
                          packageName: _logcatPackageTarget(),
                        ),
                      ),
                icon: const Icon(Icons.badge_rounded),
                label: isZh ? '身份验签' : 'Identity',
              ),
              _DashboardActionButton(
                onPressed: staticBusy
                    ? null
                    : () => _runStaticAction(
                        () => _ctrl.runJadxDecompile(
                          apkPath: _ctrl.config.apkPath,
                          packageName: _logcatPackageTarget(),
                        ),
                      ),
                icon: const Icon(Icons.code_rounded),
                label: isZh ? 'jadx 反编译' : 'jadx',
              ),
              _DashboardActionButton(
                onPressed: staticBusy
                    ? null
                    : () => _runStaticAction(
                        () => _ctrl.runApktoolUnpack(
                          apkPath: _ctrl.config.apkPath,
                          packageName: _logcatPackageTarget(),
                        ),
                      ),
                icon: const Icon(Icons.inventory_2_rounded),
                label: isZh ? 'apktool 解包' : 'apktool',
              ),
              _DashboardActionButton(
                onPressed: staticBusy
                    ? null
                    : () => _runStaticAction(
                        () => _ctrl.runStaticStringsScan(
                          apkPath: _ctrl.config.apkPath,
                          packageName: _logcatPackageTarget(),
                        ),
                      ),
                icon: const Icon(Icons.search_rounded),
                label: isZh ? '字符串扫描' : 'Strings',
              ),
              if (scanOutput != null && scanOutput.isNotEmpty) ...[
                _DashboardActionButton(
                  onPressed: () => _copyText(scanOutput),
                  icon: const Icon(Icons.copy_rounded),
                  label: isZh ? '复制结果' : 'Copy result',
                ),
              ],
            ],
          ),
          if (scanOutput != null && scanOutput.isNotEmpty) ...[
            const SizedBox(height: 10),
            _monospaceCard(cs, scanOutput),
          ],
        ],
      ),
    );
  }

  // ── Certs tab ────────────────────────────────────────────────────────────

  Widget _buildCertsTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final artifactOutput = _certificateArtifactOutput?.trim();
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _dashboardSectionHeader(
            leading: const [],
            actions: [
              _DashboardActionButton(
                onPressed: _writingCertificateArtifacts
                    ? null
                    : _ensureCertificateArtifacts,
                icon: _writingCertificateArtifacts
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.description_rounded),
                label: isZh ? '生成证书工件' : 'Generate cert artifacts',
              ),
              _DashboardActionButton(
                onPressed: _runningCertificateAction
                    ? null
                    : _readCertificateArtifacts,
                icon: _runningCertificateAction
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.folder_open_rounded),
                label: isZh ? '读取工件' : 'Read artifacts',
              ),
              _DashboardActionButton(
                onPressed: _runningCertificateAction
                    ? null
                    : _generateDebugKeystore,
                icon: _runningCertificateAction
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.key_rounded),
                label: isZh ? '生成密钥库' : 'Generate keystore',
              ),
              _DashboardActionButton(
                onPressed: _runningCertificateAction
                    ? null
                    : _verifyConfiguredApkSignature,
                icon: _runningCertificateAction
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.verified_rounded),
                label: isZh ? '验签 APK' : 'Verify APK',
              ),
              _DashboardActionButton(
                onPressed: _runningCertificateAction
                    ? null
                    : _inspectMitmproxyCa,
                icon: _runningCertificateAction
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.policy_rounded),
                label: isZh ? '检查 CA' : 'Inspect CA',
              ),
              _DashboardActionButton(
                onPressed: _runningCertificateAction
                    ? null
                    : _installMitmproxySystemCa,
                icon: _runningCertificateAction
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : const Icon(Icons.security_update_good_rounded),
                label: isZh ? '安装系统 CA' : 'Install system CA',
              ),
              if (artifactOutput != null && artifactOutput.isNotEmpty)
                _DashboardActionButton(
                  onPressed: () => _copyText(artifactOutput),
                  icon: const Icon(Icons.copy_rounded),
                  label: isZh ? '复制结果' : 'Copy result',
                ),
            ],
          ),
          const SizedBox(height: 12),
          _pathTextField(
            controller: _mitmCertPathCtrl,
            hintText: isZh
                ? 'mitmproxy CA 路径，留默认使用 ~/.mitmproxy/mitmproxy-ca-cert.pem'
                : 'mitmproxy CA path, default ~/.mitmproxy/mitmproxy-ca-cert.pem',
          ),
          const SizedBox(height: 10),
          if (artifactOutput != null && artifactOutput.isNotEmpty)
            _monospaceCard(cs, artifactOutput),
        ],
      ),
    );
  }

  // ── Crypto pad tab ────────────────────────────────────────────────────────

  Widget _buildCryptoTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final cryptoOutput = _base64OutCtrl.text.trim();
    return OpenHandSafeScrollbar(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _base64Ctrl,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              isDense: true,
              hintText: isZh
                  ? '粘贴文本、Base64、URL 编码、JWT、密钥材料或待哈希内容...'
                  : 'Paste text, Base64, URL encoding, JWT, key material, or content to hash...',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          _dashboardActionWrap(
            [
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _setCryptoOutput(
                        isZh ? 'Base64 编码' : 'Base64 encode',
                        base64Encode(utf8.encode(_base64Ctrl.text)),
                      ),
                icon: const Icon(Icons.upload_rounded),
                label: isZh ? 'Base64 编码' : 'B64 encode',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _decodeBase64Input(isZh),
                icon: const Icon(Icons.download_rounded),
                label: isZh ? 'Base64 解码' : 'B64 decode',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _setCryptoOutput(
                        isZh ? 'URL 编码' : 'URL encode',
                        Uri.encodeComponent(_base64Ctrl.text),
                      ),
                icon: const Icon(Icons.link_rounded),
                label: isZh ? 'URL 编码' : 'URL encode',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _decodeUrlInput(isZh),
                icon: const Icon(Icons.link_off_rounded),
                label: isZh ? 'URL 解码' : 'URL decode',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _hashCryptoInput('MD5', crypto.md5),
                icon: const Icon(Icons.tag_rounded),
                label: 'MD5',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _hashCryptoInput('SHA1', crypto.sha1),
                icon: const Icon(Icons.tag_rounded),
                label: 'SHA1',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _hashCryptoInput('SHA256', crypto.sha256),
                icon: const Icon(Icons.tag_rounded),
                label: 'SHA256',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _hashCryptoInput('SHA512', crypto.sha512),
                icon: const Icon(Icons.tag_rounded),
                label: 'SHA512',
              ),
              _DashboardActionButton(
                onPressed: _base64Ctrl.text.isEmpty
                    ? null
                    : () => _decodeJwtInput(isZh),
                icon: const Icon(Icons.token_rounded),
                label: isZh ? 'JWT 解析' : 'JWT decode',
              ),
              _DashboardActionButton(
                onPressed: _cryptoCopyValue.isEmpty
                    ? null
                    : () => _copyText(_cryptoCopyValue),
                icon: const Icon(Icons.copy_rounded),
                label: isZh ? '复制结果' : 'Copy result',
              ),
            ],
            alignment: Alignment.centerLeft,
            wrapAlignment: WrapAlignment.start,
          ),
          const SizedBox(height: 12),
          if (cryptoOutput.isNotEmpty) _monospaceCard(cs, _base64OutCtrl.text),
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

  Widget _dashboardSectionHeader({
    required List<Widget> leading,
    required List<Widget> actions,
  }) {
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final leadingWrap = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: leading,
          );
          final actionWrap = _dashboardActionWrap(actions);
          if (leading.isEmpty) {
            return actionWrap;
          }
          if (actions.isEmpty) {
            return Align(alignment: Alignment.centerLeft, child: leadingWrap);
          }
          final maxWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : _kDashboardDialogMaxWidth;
          if (maxWidth < _kDashboardHeaderCompactBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [leadingWrap, const SizedBox(height: 8), actionWrap],
            );
          }
          final leadingMaxWidth =
              maxWidth * _kDashboardHeaderLeadingMaxWidthRatio;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: leadingMaxWidth > _kDashboardHeaderLeadingMaxWidth
                      ? _kDashboardHeaderLeadingMaxWidth
                      : leadingMaxWidth,
                ),
                child: leadingWrap,
              ),
              const SizedBox(width: 12),
              Expanded(child: actionWrap),
            ],
          );
        },
      ),
    );
  }

  Widget _dashboardActionWrap(
    List<Widget> actions, {
    AlignmentGeometry alignment = Alignment.centerRight,
    WrapAlignment wrapAlignment = WrapAlignment.end,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: alignment,
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: wrapAlignment,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ),
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

  List<McpServer> _matchingAndroidMcpServersForCapability(
    McpController controller,
    TemplateRuntimeMcpCapabilitySpec capability,
  ) {
    final suggestedName = capability.suggestedServerName?.trim();
    final exactMatches = suggestedName == null || suggestedName.isEmpty
        ? const <McpServer>[]
        : controller.servers
              .where(
                (server) =>
                    server.name.toLowerCase() == suggestedName.toLowerCase(),
              )
              .toList(growable: false);
    if (exactMatches.isNotEmpty) return exactMatches;
    return controller.servers
        .where(
          (server) => TemplateRuntimeDependencyRegistry.containsAnyKeyword(
            _mcpServerSearchText(controller, server),
            capability.keywords,
          ),
        )
        .toList(growable: false);
  }

  String _mcpServerSearchText(McpController controller, McpServer server) {
    final catalog = controller.toolCatalogFor(server.name);
    final buffer = StringBuffer()
      ..write(server.name)
      ..write(' ')
      ..write(server.summary)
      ..write(' ')
      ..write(server.type.transportValue);
    for (final tool in catalog.tools) {
      buffer
        ..write(' ')
        ..write(tool.id)
        ..write(' ')
        ..write(tool.name)
        ..write(' ')
        ..write(tool.description);
    }
    return buffer.toString();
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
    final plugin = _toolchainPluginForProbe(probe);
    if (plugin != null) {
      return <_ToolchainCommandAction>[
        if (plugin.isInstalled)
          _ToolchainCommandAction.update
        else
          _ToolchainCommandAction.install,
        if (plugin.isInstalled && plugin.supportsUninstall)
          _ToolchainCommandAction.uninstall,
        _ToolchainCommandAction.reference,
      ];
    }
    final installed = _toolchainResultForProbe(probe)?.ok;
    return <_ToolchainCommandAction>[
      if (installed != true) _ToolchainCommandAction.install,
      if (installed == true &&
          (probe.updateCommand?.trim().isNotEmpty ?? false))
        _ToolchainCommandAction.update,
      if (installed == true &&
          (probe.uninstallCommand?.trim().isNotEmpty ?? false))
        _ToolchainCommandAction.uninstall,
      _ToolchainCommandAction.reference,
    ];
  }

  AndroidReverseToolchainProbeResult? _toolchainResultForProbe(
    AndroidReverseToolchainProbe probe,
  ) {
    return _toolchainRows.where((row) => row.probe.id == probe.id).firstOrNull;
  }

  bool _isToolchainCommandRunning(
    AndroidReverseToolchainProbe probe,
    _ToolchainCommandAction action,
  ) {
    return _runningToolchainCommandIds.contains(
      _toolchainCommandKey(probe, action),
    );
  }

  String _toolchainCommandKey(
    AndroidReverseToolchainProbe probe,
    _ToolchainCommandAction action,
  ) {
    return '${probe.id}:${action.name}';
  }

  PluginInfo? _toolchainPluginForProbe(
    AndroidReverseToolchainProbe probe, [
    PluginServiceController? pluginController,
  ]) {
    final pluginId = androidReverseToolchainPluginIdForProbe(probe.id);
    if (pluginId == null) return null;
    return (pluginController ?? context.read<PluginServiceController>())
        .pluginById(pluginId);
  }

  Future<void> _handleToolchainAction(
    AndroidReverseToolchainProbe probe,
    _ToolchainCommandAction action,
    bool isZh,
  ) async {
    if (_isToolchainCommandRunning(probe, action)) return;
    if (action == _ToolchainCommandAction.reference) {
      _showToolchainInfoDialog(probe, isZh);
      return;
    }
    final plugin = _toolchainPluginForProbe(probe);
    if (plugin != null) {
      await _handleToolchainPluginAction(probe, plugin, action, isZh);
      return;
    }
    final commandAction = _toolchainCommandAction(action);
    if (commandAction == null) return;
    final command = probe.commandFor(commandAction)?.trim() ?? '';
    if (command.isEmpty) {
      _showSnack(
        isZh
            ? '${probe.label} 暂无可自动执行的${_toolchainCommandLabel(action, isZh)}命令。'
            : 'No executable ${_toolchainCommandLabel(action, isZh).toLowerCase()} command is available for ${probe.label}.',
      );
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title:
          '${_toolchainCommandLabel(action, isZh)} ${probe.label}${isZh ? "？" : "?"}',
      message: [
        isZh
            ? 'OpenHand 将直接执行以下命令，完成后自动刷新工具链诊断。'
            : 'OpenHand will run the command below and refresh toolchain diagnostics afterwards.',
        '',
        command,
      ].join('\n'),
      cancelLabel: isZh ? '取消' : 'Cancel',
      confirmLabel: _toolchainCommandLabel(action, isZh),
      destructive: action == _ToolchainCommandAction.uninstall,
    );
    if (!confirmed || !mounted) return;
    final key = _toolchainCommandKey(probe, action);
    setState(() {
      _runningToolchainCommandIds.add(key);
      _lastToolchainCommandResult = AdbCommandResult(
        args: <String>['toolchain', action.name, probe.id],
        exitCode: -1,
        stdout: isZh ? '执行中...' : 'Running...',
        stderr: '',
        displayCommand: command,
      );
    });
    try {
      final result = await runAndroidReverseToolchainCommand(
        probe,
        commandAction,
      );
      if (!mounted) return;
      final adbResult = AdbCommandResult(
        args: <String>['toolchain', action.name, probe.id],
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
        timedOut: result.timedOut,
        displayCommand: result.command,
      );
      setState(() => _lastToolchainCommandResult = adbResult);
      _showSnack(
        adbResult.ok
            ? (isZh
                  ? '${probe.label} ${_toolchainCommandLabel(action, isZh)}完成'
                  : '${probe.label} ${_toolchainCommandLabel(action, isZh).toLowerCase()} completed')
            : (isZh
                  ? '${probe.label} ${_toolchainCommandLabel(action, isZh)}失败'
                  : '${probe.label} ${_toolchainCommandLabel(action, isZh).toLowerCase()} failed'),
      );
      unawaited(_refreshToolchain());
    } finally {
      if (mounted) {
        setState(() => _runningToolchainCommandIds.remove(key));
      }
    }
  }

  void _showToolchainInfoDialog(AndroidReverseToolchainProbe probe, bool isZh) {
    final row = _toolchainResultForProbe(probe);
    final plugin = _toolchainPluginForProbe(probe);
    showAndroidReverseToolDialog<void>(
      context: context,
      builder: (_) => _ToolchainInfoDialog(
        probe: probe,
        result: row,
        plugin: plugin,
        isZh: isZh,
      ),
    );
  }

  Future<void> _handleToolchainPluginAction(
    AndroidReverseToolchainProbe probe,
    PluginInfo plugin,
    _ToolchainCommandAction action,
    bool isZh,
  ) async {
    final runtimeAction = switch (action) {
      _ToolchainCommandAction.install => _RuntimePluginAction.install,
      _ToolchainCommandAction.update => _RuntimePluginAction.update,
      _ToolchainCommandAction.uninstall => _RuntimePluginAction.uninstall,
      _ToolchainCommandAction.reference => null,
    };
    if (runtimeAction == null) return;
    if (action == _ToolchainCommandAction.update && !plugin.isInstalled) {
      _showSnack(
        isZh ? '${plugin.name} 尚未安装。' : '${plugin.name} is not installed.',
      );
      return;
    }
    if (action == _ToolchainCommandAction.uninstall && !plugin.isInstalled) {
      _showSnack(
        isZh ? '${plugin.name} 尚未安装。' : '${plugin.name} is not installed.',
      );
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title:
          '${_toolchainCommandLabel(action, isZh)} ${probe.label}${isZh ? "？" : "?"}',
      message: isZh
          ? 'OpenHand 将通过插件服务直接${_toolchainCommandLabel(action, isZh)} ${plugin.name}，完成后自动刷新插件和工具链状态。'
          : 'OpenHand will ${_toolchainCommandLabel(action, isZh).toLowerCase()} ${plugin.name} through the plugin service, then refresh plugin and toolchain status.',
      cancelLabel: isZh ? '取消' : 'Cancel',
      confirmLabel: _toolchainCommandLabel(action, isZh),
      destructive: action == _ToolchainCommandAction.uninstall,
    );
    if (!confirmed || !mounted) return;
    final key = _toolchainCommandKey(probe, action);
    final pluginController = context.read<PluginServiceController>();
    setState(() {
      _runningToolchainCommandIds.add(key);
      _lastToolchainCommandResult = AdbCommandResult(
        args: <String>['toolchain-plugin', action.name, plugin.id],
        exitCode: -1,
        stdout: isZh ? '插件服务执行中...' : 'Plugin service is running...',
        stderr: '',
        displayCommand: 'plugin:${plugin.id} ${action.name}',
      );
    });
    try {
      final success = switch (runtimeAction) {
        _RuntimePluginAction.install => await pluginController.installPlugin(
          plugin.id,
        ),
        _RuntimePluginAction.update => await pluginController.updatePlugin(
          plugin.id,
        ),
        _RuntimePluginAction.uninstall =>
          await pluginController.uninstallPlugin(plugin.id),
        _ => false,
      };
      if (!mounted) return;
      final latest = pluginController.pluginById(plugin.id) ?? plugin;
      final logs = pluginController.operationLogs.join('\n').trim();
      final stdout = <String>[
        '${isZh ? "插件" : "Plugin"}: ${latest.name}',
        '${isZh ? "动作" : "Action"}: ${_toolchainCommandLabel(action, isZh)}',
        '${isZh ? "状态" : "Status"}: ${success ? (isZh ? "完成" : "completed") : (isZh ? "失败" : "failed")}',
        if (latest.installedVersion?.trim().isNotEmpty ?? false)
          '${isZh ? "版本" : "Version"}: ${latest.installedVersion}',
        if (latest.installPath?.trim().isNotEmpty ?? false)
          '${isZh ? "路径" : "Path"}: ${latest.installPath}',
        if (logs.isNotEmpty) ...['', logs],
      ].join('\n');
      setState(() {
        _lastToolchainCommandResult = AdbCommandResult(
          args: <String>['toolchain-plugin', action.name, plugin.id],
          exitCode: success ? 0 : -1,
          stdout: stdout,
          stderr: success
              ? ''
              : (pluginController.errorMessage ??
                    latest.errorMessage ??
                    (isZh ? '插件服务动作失败。' : 'Plugin service action failed.')),
          displayCommand: 'plugin:${plugin.id} ${action.name}',
        );
      });
      _showSnack(
        success
            ? (isZh
                  ? '${plugin.name} ${_toolchainCommandLabel(action, isZh)}完成'
                  : '${plugin.name} ${_toolchainCommandLabel(action, isZh).toLowerCase()} completed')
            : (isZh
                  ? '${plugin.name} ${_toolchainCommandLabel(action, isZh)}失败'
                  : '${plugin.name} ${_toolchainCommandLabel(action, isZh).toLowerCase()} failed'),
      );
      unawaited(_refreshToolchain());
    } finally {
      if (mounted) {
        setState(() => _runningToolchainCommandIds.remove(key));
      }
    }
  }

  AndroidReverseToolchainCommandAction? _toolchainCommandAction(
    _ToolchainCommandAction action,
  ) {
    return switch (action) {
      _ToolchainCommandAction.install =>
        AndroidReverseToolchainCommandAction.install,
      _ToolchainCommandAction.update =>
        AndroidReverseToolchainCommandAction.update,
      _ToolchainCommandAction.uninstall =>
        AndroidReverseToolchainCommandAction.uninstall,
      _ToolchainCommandAction.reference => null,
    };
  }

  IconData _toolchainCommandIcon(_ToolchainCommandAction action) {
    return switch (action) {
      _ToolchainCommandAction.install => Icons.download_rounded,
      _ToolchainCommandAction.update => Icons.upgrade_rounded,
      _ToolchainCommandAction.uninstall => Icons.delete_outline_rounded,
      _ToolchainCommandAction.reference => Icons.info_outline_rounded,
    };
  }

  String _toolchainCommandLabel(_ToolchainCommandAction action, bool isZh) {
    return switch (action) {
      _ToolchainCommandAction.install => isZh ? '安装' : 'Install',
      _ToolchainCommandAction.update => isZh ? '更新' : 'Update',
      _ToolchainCommandAction.uninstall => isZh ? '卸载' : 'Uninstall',
      _ToolchainCommandAction.reference => isZh ? '查看信息' : 'Info',
    };
  }

  String _mcpResolvedToolName(McpServer server, McpTool tool) {
    return compactToolName(prefix: 'mcp__${server.name}', token: tool.id);
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

  Widget _monospaceCard(ColorScheme cs, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: _formattedTerminalText(text, cs),
    );
  }

  Widget _formattedTerminalText(String text, ColorScheme cs) {
    final formatted = formatStructuredTextForDisplay(text);
    final label = formatted.format == null
        ? null
        : structuredTextFormatLabel(formatted.format!);
    final base = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: cs.onSurface,
      height: 1.5,
    );
    final content = ansiText(formatted.text, colorScheme: cs, base: base);
    if (label == null) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusPill(label: label, color: cs.primary),
        const SizedBox(height: 6),
        content,
      ],
    );
  }

  Widget _buildAdbCommandResultView(
    AdbCommandResult result,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    final ok = result.ok || result.partialOk;
    final statusColor = ok ? cs.primary : cs.error;
    final stdout = result.stdout.trim();
    final stderr = result.stderr.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusPill(
              label: ok
                  ? result.partialOk
                        ? (isZh ? '部分完成' : 'partial')
                        : (isZh ? '成功' : 'success')
                  : (isZh ? '失败' : 'failed'),
              color: statusColor,
            ),
            _StatusPill(
              label: '${isZh ? "退出码" : "exit"} ${result.exitCode}',
              color: statusColor,
            ),
            if (result.timedOut)
              _StatusPill(label: isZh ? '超时' : 'timeout', color: cs.tertiary),
          ],
        ),
        const SizedBox(height: 8),
        _resultSection(cs, theme, isZh ? '命令' : 'Command', result.commandLine),
        if (stdout.isNotEmpty) ...[
          const SizedBox(height: 8),
          _resultSection(cs, theme, 'stdout', stdout),
        ],
        if (stderr.isNotEmpty) ...[
          const SizedBox(height: 8),
          _resultSection(cs, theme, 'stderr', stderr, isError: !ok),
        ],
        if (stdout.isEmpty && stderr.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            isZh ? '(命令无输出)' : '(no output)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _resultSection(
    ColorScheme cs,
    ThemeData theme,
    String title,
    String text, {
    bool isError = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isError
            ? cs.errorContainer.withValues(alpha: 0.18)
            : cs.surface.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (isError ? cs.error : cs.outlineVariant).withValues(
            alpha: 0.42,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isError ? cs.error : cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          _formattedTerminalText(text, cs),
        ],
      ),
    );
  }

  void _setCryptoOutput(String title, String output) {
    final value = output.trimRight();
    setState(() {
      _cryptoCopyValue = value;
      _base64OutCtrl.text = [
        '# $title',
        value.isEmpty ? '(empty)' : value,
      ].join('\n');
    });
  }

  void _decodeBase64Input(bool isZh) {
    try {
      final normalized = _base64Ctrl.text.replaceAll(RegExp(r'\s+'), '');
      final decoded = utf8.decode(base64Decode(base64.normalize(normalized)));
      _setCryptoOutput(isZh ? 'Base64 解码' : 'Base64 decode', decoded);
    } catch (error) {
      _setCryptoOutput(isZh ? 'Base64 解码失败' : 'Base64 decode failed', '$error');
    }
  }

  void _decodeUrlInput(bool isZh) {
    try {
      _setCryptoOutput(
        isZh ? 'URL 解码' : 'URL decode',
        Uri.decodeComponent(_base64Ctrl.text),
      );
    } catch (error) {
      _setCryptoOutput(isZh ? 'URL 解码失败' : 'URL decode failed', '$error');
    }
  }

  void _hashCryptoInput(String label, crypto.Hash algorithm) {
    final bytes = utf8.encode(_base64Ctrl.text);
    _setCryptoOutput(label, algorithm.convert(bytes).toString());
  }

  void _decodeJwtInput(bool isZh) {
    try {
      final token = _base64Ctrl.text.trim();
      final parts = token.split('.');
      if (parts.length < 2) {
        throw const FormatException('JWT must contain header and payload.');
      }
      final header = _decodeJwtSegment(parts[0]);
      final payload = _decodeJwtSegment(parts[1]);
      const encoder = JsonEncoder.withIndent('  ');
      final headerText = encoder.convert(jsonDecode(header));
      final payloadText = encoder.convert(jsonDecode(payload));
      _setCryptoOutput(
        isZh ? 'JWT 解析' : 'JWT decode',
        [
          '## header',
          headerText,
          '',
          '## payload',
          payloadText,
          if (parts.length > 2) ...['', '## signature', parts[2]],
        ].join('\n'),
      );
    } catch (error) {
      _setCryptoOutput(isZh ? 'JWT 解析失败' : 'JWT decode failed', '$error');
    }
  }

  String _decodeJwtSegment(String segment) {
    return utf8.decode(base64Url.decode(base64Url.normalize(segment)));
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
          width: _kDeviceTrailingActionWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _DashboardActionButton(
              onPressed: onPressed,
              icon: Icon(icon),
              label: label,
            ),
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

  String _normalizeAdbShellInput(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    final adbShellPrefix = RegExp(
      r"""^adb(?:\s+(?:-s\s+(?:"[^"]+"|'[^']+'|\S+)|-d|-e|-a|-t\s+\S+|-H\s+\S+|-P\s+\S+))*\s+shell(?:\s+(?:-T|-t|-tt|-x|-n|--))*\s*""",
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

  String _shellQuote(String value) {
    if (RegExp(r'^[A-Za-z0-9_./:@%+=,-]+$').hasMatch(value)) {
      return value;
    }
    return "'${value.replaceAll("'", "'\"'\"'")}'";
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

class _ParsedLogcatLine {
  const _ParsedLogcatLine({
    required this.raw,
    required this.message,
    this.level,
    this.time,
    this.pid,
    this.tid,
    this.tag,
  });

  final String raw;
  final String message;
  final String? level;
  final String? time;
  final String? pid;
  final String? tid;
  final String? tag;
}

class _LogcatLineTile extends StatelessWidget {
  const _LogcatLineTile({
    required this.parsed,
    required this.colorScheme,
    required this.theme,
    required this.isZh,
    required this.onMenu,
  });

  final _ParsedLogcatLine parsed;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final bool isZh;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final level = parsed.level?.trim().toUpperCase();
    final color = _levelColor(level, colorScheme);
    final meta = <String>[
      if (parsed.time?.trim().isNotEmpty ?? false) parsed.time!.trim(),
      if (parsed.pid?.trim().isNotEmpty ?? false)
        (parsed.tid?.trim().isNotEmpty ?? false)
            ? 'pid ${parsed.pid}/${parsed.tid}'
            : 'pid ${parsed.pid}',
      if (parsed.tag?.trim().isNotEmpty ?? false) parsed.tag!.trim(),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => onMenu(details.globalPosition),
      onDoubleTapDown: (details) => onMenu(details.globalPosition),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: level == null ? 0.03 : 0.07),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                level == null ? '-' : _shortLevelLabel(level, isZh),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (meta.isNotEmpty)
                    Text(
                      meta.join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                        height: 1.25,
                      ),
                    ),
                  Text(
                    parsed.message.isEmpty ? parsed.raw : parsed.message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: level == 'E' || level == 'F'
                          ? color
                          : colorScheme.onSurface,
                      height: 1.36,
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

  Color _levelColor(String? level, ColorScheme cs) {
    return switch (level) {
      'F' => const Color(0xFF8B1E1E),
      'E' => cs.error,
      'W' => const Color(0xFFB26A00),
      'I' => const Color(0xFF1E63B6),
      'D' => const Color(0xFF7B4BB3),
      'V' => cs.outline,
      _ => cs.onSurfaceVariant,
    };
  }

  String _shortLevelLabel(String level, bool isZh) {
    return switch (level) {
      'V' => isZh ? '详' : 'V',
      'D' => isZh ? '调' : 'D',
      'I' => isZh ? '信' : 'I',
      'W' => isZh ? '警' : 'W',
      'E' => isZh ? '错' : 'E',
      'F' => isZh ? '致' : 'F',
      _ => level,
    };
  }
}

class _DashboardActionButton extends StatelessWidget {
  const _DashboardActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.height = _kDashboardActionButtonHeight,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = FilledButton.styleFrom(
      minimumSize: const Size(0, _kDashboardActionButtonHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      textStyle: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    );
    final effectiveIcon = IconTheme.merge(
      data: const IconThemeData(size: _kDashboardActionIconSize),
      child: icon,
    );
    final labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
    return SizedBox(
      height: height,
      child: filled
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: effectiveIcon,
              label: labelWidget,
              style: style,
            )
          : FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: effectiveIcon,
              label: labelWidget,
              style: style,
            ),
    );
  }
}

ButtonStyle _dashboardIconActionStyle(ColorScheme cs) {
  return ButtonStyle(
    fixedSize: const WidgetStatePropertyAll<Size>(
      Size.square(_kDashboardIconActionButtonSize),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(
      Size.square(_kDashboardIconActionButtonSize),
    ),
    maximumSize: const WidgetStatePropertyAll<Size>(
      Size.square(_kDashboardIconActionButtonSize),
    ),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const WidgetStatePropertyAll<OutlinedBorder>(CircleBorder()),
    backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return cs.surfaceContainerHighest.withValues(alpha: 0.46);
      }
      if (states.contains(WidgetState.pressed)) {
        return cs.secondaryContainer.withValues(alpha: 0.92);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return cs.secondaryContainer.withValues(alpha: 0.72);
      }
      return cs.surfaceContainerHighest.withValues(alpha: 0.86);
    }),
    foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurfaceVariant;
    }),
    iconColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurfaceVariant;
    }),
    overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return cs.primary.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return cs.primary.withValues(alpha: 0.08);
      }
      return null;
    }),
  );
}

class _DashboardIconActionButton extends StatelessWidget {
  const _DashboardIconActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: _kDashboardIconActionButtonSize,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        splashRadius: _kDashboardIconActionButtonSize / 2,
        style: _dashboardIconActionStyle(cs),
        icon: IconTheme.merge(
          data: const IconThemeData(size: _kDashboardIconActionIconSize),
          child: icon,
        ),
      ),
    );
  }
}

class _DashboardPopupIconActionButton<T> extends StatelessWidget {
  const _DashboardPopupIconActionButton({
    required this.icon,
    required this.tooltip,
    required this.itemBuilder,
    required this.onSelected,
    this.enabled = true,
  });

  final Widget icon;
  final String tooltip;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: _kDashboardIconActionButtonSize,
      child: IconButtonTheme(
        data: IconButtonThemeData(style: _dashboardIconActionStyle(cs)),
        child: AnimatedPopupMenuButton<T>(
          tooltip: tooltip,
          enabled: enabled,
          icon: IconTheme.merge(
            data: const IconThemeData(size: _kDashboardIconActionIconSize),
            child: icon,
          ),
          iconSize: _kDashboardIconActionIconSize,
          padding: EdgeInsets.zero,
          splashRadius: _kDashboardIconActionButtonSize / 2,
          buttonConstraints: const BoxConstraints.tightFor(
            width: _kDashboardIconActionButtonSize,
            height: _kDashboardIconActionButtonSize,
          ),
          itemBuilder: itemBuilder,
          onSelected: onSelected,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    this.compact = false,
    this.subtle = false,
  });

  final String label;
  final Color color;
  final bool compact;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: subtle
            ? cs.surfaceContainerHighest.withValues(alpha: 0.56)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: subtle ? 0.24 : 0.36),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 10.5 : null,
          height: 1.05,
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
    required this.removeTooltip,
  });

  final String row;
  final ColorScheme colorScheme;
  final VoidCallback? onRemove;
  final String removeTooltip;

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
            tooltip: removeTooltip,
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
    return _DashboardActionButton(
      onPressed: onPressed,
      icon: Icon(icon),
      label: label,
    );
  }
}

String _runtimePluginStatusLabel(PluginInfo plugin, bool isZh) {
  return switch (plugin.status) {
    PluginStatus.notInstalled => isZh ? '未安装' : 'Not installed',
    PluginStatus.installed =>
      plugin.enabled
          ? (isZh ? '已安装并启用' : 'Installed and enabled')
          : (isZh ? '已安装但禁用' : 'Installed but disabled'),
    PluginStatus.installing => isZh ? '安装中' : 'Installing',
    PluginStatus.updating => isZh ? '更新中' : 'Updating',
    PluginStatus.uninstalling => isZh ? '卸载中' : 'Uninstalling',
    PluginStatus.error => isZh ? '异常' : 'Error',
  };
}

class _ToolchainInfoDialog extends StatelessWidget {
  const _ToolchainInfoDialog({
    required this.probe,
    required this.result,
    required this.plugin,
    required this.isZh,
  });

  final AndroidReverseToolchainProbe probe;
  final AndroidReverseToolchainProbeResult? result;
  final PluginInfo? plugin;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final installed = result?.ok ?? plugin?.isInstalled;
    final statusColor = installed == true
        ? cs.primary
        : installed == false
        ? cs.error
        : cs.outline;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 560,
      maxHeight: 640,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.info_outline_rounded,
            title: '${probe.label} ${isZh ? "详情" : "Details"}',
            subtitle: probe.id,
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(
            child: OpenHandSafeScrollbar(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _DashboardDetailSection(
                    title: isZh ? '基本信息' : 'Basic info',
                    icon: Icons.construction_rounded,
                    children: [
                      _DashboardDetailRow(
                        label: isZh ? '名称' : 'Name',
                        value: probe.label,
                      ),
                      _DashboardDetailRow(label: 'ID', value: probe.id),
                      _DashboardDetailRow(
                        label: isZh ? '类型' : 'Type',
                        value: plugin == null
                            ? (isZh ? '系统工具链' : 'System toolchain')
                            : (isZh ? '插件托管工具' : 'Plugin-managed tool'),
                      ),
                      _DashboardDetailRow(
                        label: isZh ? '必要' : 'Required',
                        value: probe.required
                            ? (isZh ? '是' : 'Yes')
                            : (isZh ? '否' : 'No'),
                      ),
                      _DashboardDetailRow(
                        label: isZh ? '状态' : 'Status',
                        value: installed == true
                            ? (isZh ? '已安装' : 'Installed')
                            : installed == false
                            ? (isZh ? '未安装' : 'Not installed')
                            : (isZh ? '未检测' : 'Not checked'),
                        valueColor: statusColor,
                      ),
                    ],
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 14),
                    _DashboardDetailSection(
                      title: isZh ? '诊断结果' : 'Diagnostic',
                      icon: Icons.fact_check_rounded,
                      accentColor: statusColor,
                      children: [
                        _DashboardDetailRow(
                          label: isZh ? '输出' : 'Output',
                          value: result!.displayValue,
                          monospace: true,
                          valueColor: result!.ok ? null : cs.error,
                        ),
                        _DashboardDetailRow(
                          label: isZh ? '退出码' : 'Exit code',
                          value: '${result!.exitCode}',
                          monospace: true,
                        ),
                        _DashboardDetailRow(
                          label: isZh ? '耗时' : 'Duration',
                          value: '${result!.durationMs}ms',
                          monospace: true,
                        ),
                        if (result!.stderr.trim().isNotEmpty)
                          _DashboardDetailRow(
                            label: isZh ? '错误' : 'Error',
                            value: result!.stderr.trim(),
                            valueColor: cs.error,
                            monospace: true,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  _DashboardDetailSection(
                    title: isZh ? '可用操作' : 'Available actions',
                    icon: Icons.terminal_rounded,
                    children: [
                      _DashboardDetailRow(
                        label: isZh ? '安装' : 'Install',
                        value:
                            _commandText(probe.installCommand) ??
                            (isZh ? probe.installHintZh : probe.installHintEn),
                        monospace:
                            probe.installCommand?.trim().isNotEmpty ?? false,
                      ),
                      _DashboardDetailRow(
                        label: isZh ? '更新' : 'Update',
                        value: _commandText(probe.updateCommand),
                        monospace: true,
                      ),
                      _DashboardDetailRow(
                        label: isZh ? '卸载' : 'Uninstall',
                        value: _commandText(probe.uninstallCommand),
                        monospace: true,
                      ),
                      _DashboardDetailRow(
                        label: isZh ? '参考' : 'Reference',
                        value: _commandText(probe.referenceUrl),
                        monospace: true,
                      ),
                    ],
                  ),
                  if (plugin != null) ...[
                    const SizedBox(height: 14),
                    _DashboardDetailSection(
                      title: isZh ? '关联插件' : 'Linked plugin',
                      icon: Icons.extension_rounded,
                      children: [
                        _DashboardDetailRow(
                          label: isZh ? '名称' : 'Name',
                          value: plugin!.name,
                        ),
                        _DashboardDetailRow(label: 'ID', value: plugin!.id),
                        _DashboardDetailRow(
                          label: isZh ? '描述' : 'Description',
                          value: plugin!.description,
                        ),
                        _DashboardDetailRow(
                          label: isZh ? '状态' : 'Status',
                          value: _runtimePluginStatusLabel(plugin!, isZh),
                          valueColor: plugin!.isInstalled
                              ? plugin!.enabled
                                    ? cs.primary
                                    : cs.outline
                              : plugin!.status == PluginStatus.error
                              ? cs.error
                              : cs.tertiary,
                        ),
                        _DashboardDetailRow(
                          label: isZh ? '版本' : 'Version',
                          value: plugin!.installedVersion,
                        ),
                        _DashboardDetailRow(
                          label: isZh ? '路径' : 'Path',
                          value: plugin!.installPath,
                          monospace: true,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _commandText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class _RuntimePluginInfoDialog extends StatelessWidget {
  const _RuntimePluginInfoDialog({required this.plugin, required this.isZh});

  final PluginInfo plugin;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final specs = TemplateRuntimeDependencyRegistry.specsForPlugin(plugin.id);
    final statusColor = plugin.isInstalled
        ? plugin.enabled
              ? cs.primary
              : cs.outline
        : plugin.status == PluginStatus.error
        ? cs.error
        : cs.tertiary;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 520,
      maxHeight: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.extension_rounded,
            title: '${plugin.name} ${isZh ? "信息" : "Info"}',
            subtitle: plugin.id,
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(
            child: OpenHandSafeScrollbar(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _DashboardDetailSection(
                    title: isZh ? '基本信息' : 'Basic info',
                    icon: Icons.info_outline_rounded,
                    children: [
                      _DashboardDetailRow(
                        label: isZh ? '名称' : 'Name',
                        value: plugin.name,
                      ),
                      _DashboardDetailRow(label: 'ID', value: plugin.id),
                      _DashboardDetailRow(
                        label: isZh ? '描述' : 'Description',
                        value: plugin.description,
                      ),
                      _DashboardDetailRow(
                        label: isZh ? '状态' : 'Status',
                        value: _runtimePluginStatusLabel(plugin, isZh),
                        valueColor: statusColor,
                      ),
                      _DashboardDetailRow(
                        label: isZh ? '启用' : 'Enabled',
                        value: plugin.enabled
                            ? (isZh ? '是' : 'Yes')
                            : (isZh ? '否' : 'No'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _DashboardDetailSection(
                    title: isZh ? '版本与路径' : 'Version and path',
                    icon: Icons.inventory_2_rounded,
                    children: [
                      _DashboardDetailRow(
                        label: isZh ? '已安装版本' : 'Installed',
                        value: plugin.installedVersion,
                      ),
                      _DashboardDetailRow(
                        label: isZh ? '最新版本' : 'Latest',
                        value: plugin.latestVersion,
                      ),
                      _DashboardDetailRow(
                        label: isZh ? '安装路径' : 'Install path',
                        value: plugin.installPath,
                        monospace: true,
                      ),
                      _DashboardDetailRow(
                        label: isZh ? '支持卸载' : 'Uninstallable',
                        value: plugin.supportsUninstall
                            ? (isZh ? '是' : 'Yes')
                            : (isZh ? '否' : 'No'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _DashboardDetailSection(
                    title: isZh ? '依赖关系' : 'Dependencies',
                    icon: Icons.account_tree_rounded,
                    children: [
                      _DashboardDetailRow(
                        label: isZh ? '依赖' : 'Depends on',
                        value: plugin.dependencies.isEmpty
                            ? (isZh ? '无' : 'None')
                            : plugin.dependencies.join(', '),
                        monospace: plugin.dependencies.isNotEmpty,
                      ),
                      _DashboardDetailRow(
                        label: isZh ? '被依赖' : 'Required by',
                        value: plugin.dependents.isEmpty
                            ? (isZh ? '无' : 'None')
                            : plugin.dependents.join(', '),
                        monospace: plugin.dependents.isNotEmpty,
                      ),
                    ],
                  ),
                  if (specs.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _DashboardDetailSection(
                      title: isZh ? '逆向模板关联' : 'Reverse templates',
                      icon: Icons.dashboard_customize_rounded,
                      children: [
                        _DashboardDetailRow(
                          label: isZh ? '关联模板' : 'Templates',
                          value: specs
                              .map((spec) => isZh ? spec.labelZh : spec.labelEn)
                              .join(', '),
                        ),
                      ],
                    ),
                  ],
                  if (plugin.errorMessage?.trim().isNotEmpty ?? false) ...[
                    const SizedBox(height: 14),
                    _DashboardDetailSection(
                      title: isZh ? '异常信息' : 'Error',
                      icon: Icons.error_outline_rounded,
                      accentColor: cs.error,
                      children: [
                        _DashboardDetailRow(
                          label: isZh ? '错误' : 'Error',
                          value: plugin.errorMessage!.trim(),
                          valueColor: cs.error,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardDetailSection extends StatelessWidget {
  const _DashboardDetailSection({
    required this.title,
    required this.icon,
    required this.children,
    this.accentColor,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = accentColor ?? cs.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
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

class _DashboardDetailRow extends StatelessWidget {
  const _DashboardDetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.monospace = false,
  });

  final String label;
  final String? value;
  final Color? valueColor;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final normalized = value?.trim();
    final display = normalized == null || normalized.isEmpty ? '-' : normalized;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              display,
              style: theme.textTheme.bodySmall?.copyWith(
                color: valueColor ?? cs.onSurface,
                fontFamily: monospace ? 'monospace' : null,
                height: 1.35,
              ),
            ),
          ),
        ],
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
