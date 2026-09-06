import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/net/tcp_port_utils.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_directory_io.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/bounded_log_buffer.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_normalization.dart';
import '../../shared/util/timer_safety.dart';
import 'android_reverse_adb_client.dart';
import 'android_reverse_session_config.dart';
import 'android_reverse_toolchain_diagnostics.dart';

const String _kTag = 'android_reverse_session_controller';
const String _kAndroidReverseBashExecutable = 'bash';
const String _kAndroidReverseChmodExecutable = 'chmod';
const String _kNetworkCaptureDisplayCommand = '启动 mitmdump 捕获';
const String _kNetworkCaptureStopDisplayCommand = '停止 mitmdump 捕获';
const String _kEvidenceBundleDisplayCommand = '生成证据包';
const String _kReadQuickScanDisplayCommand = '读取快速扫描产物';
const Duration _kDeviceWatchdogInterval = Duration(seconds: 8);
const Duration _kDeviceReportTimeout = Duration(seconds: 18);
const Duration _kPackageReportTimeout = Duration(seconds: 12);
const Duration _kStaticQuickScanTimeout = Duration(seconds: 35);
const Duration _kStaticQuickScanWarmTimeout = Duration(seconds: 18);
const Duration _kStaticQuickScanTimeoutSkew = Duration(milliseconds: 500);
const Duration _kArtifactChmodTimeout = Duration(seconds: 2);
const Duration _kArtifactFileOperationTimeout = Duration(seconds: 10);
const Duration _kEvidenceBundleTimeout = Duration(seconds: 20);
const Duration _kLocalScriptTimeout = Duration(seconds: 30);
const Duration _kLocalShellActionTimeout = Duration(seconds: 20);
const Duration _kNetworkCaptureStartupProbe = Duration(milliseconds: 900);
const Duration _kNetworkCaptureProcessStartTimeout = Duration(seconds: 10);
const Duration _kNetworkCaptureStopGrace = Duration(milliseconds: 800);
const Duration _kNetworkCaptureExitWait = Duration(milliseconds: 400);
const Duration _kRuntimeCleanupTimeout = Duration(seconds: 5);
const Duration _kStaticArtifactReadTimeout = Duration(seconds: 8);
const Duration _kStaticIdentityTimeout = Duration(seconds: 16);
const Duration _kStaticStringsTimeout = Duration(seconds: 24);
const Duration _kStaticDecompileTimeout = Duration(minutes: 3);
const int _kPackageReportSummaryMaxLines = 220;
const int _kStaticQuickScanPreviewLines = 80;
const int _kStaticQuickScanPreviewMaxBytes = 256 * kBytesPerKiB;
const int _kStaticQuickScanPreviewLineMaxCharacters = 4000;
const int _kNetworkCaptureTranscriptMaxChars = 24000;
const List<String> _kAndroidReverseMcpVisibleTemplateIds = <String>[
  'android_reverse_expert',
];
const List<String> _kAndroidReverseArtifactSubdirs = <String>[
  'devices',
  'packages',
  'apks',
  'screenshots',
  'recordings',
  'frida',
  'decompiled',
  'mcp',
  'logcat',
  'network',
  'certs',
  'scripts',
  'toolchain',
  'logs',
];

/// Android 逆向会话状态。
enum AndroidReverseSessionState { idle, running, deviceLost, stopped }

class _ResolvedStaticApk {
  const _ResolvedStaticApk({required this.apkPath, required this.slug});

  final String apkPath;
  final String slug;
}

/// 单个 Android 逆向会话的运行时编排。
///
/// 生命周期：
///   constructor → start() → [period] → stop() → dispose()
///
/// 只负责：ADB 连接状态、设备信息缓存、进程列表周期刷新。
/// Frida 注入、静态分析等高级功能均通过外部 MCP / CLI 工具完成。
class AndroidReverseSessionController extends ChangeNotifier {
  AndroidReverseSessionController({
    required this.config,
    required this.artifactsRootDir,
    String? adbPath,
    AndroidReverseAdbClient? adbClient,
  }) : _adbClient =
           adbClient ??
           AndroidReverseAdbClient(
             adbPath: adbPath,
             deviceSerial: config.deviceSerial,
           );

  final AndroidReverseSessionConfig config;
  final String artifactsRootDir;

  String get logcatJsonlPath => '$artifactsRootDir/logcat.jsonl';
  String get networkJsonlPath => '$artifactsRootDir/network.jsonl';
  String get devicesDir => '$artifactsRootDir/devices';
  String get packagesDir => '$artifactsRootDir/packages';
  String get apksDir => '$artifactsRootDir/apks';
  String get screenshotsDir => '$artifactsRootDir/screenshots';
  String get recordingsDir => '$artifactsRootDir/recordings';
  String get fridaDir => '$artifactsRootDir/frida';
  String get fridaScriptsDir => '$fridaDir/scripts';
  String get fridaOutputDir => '$fridaDir/output';
  String get fridaReadmePath => '$fridaDir/README.md';
  String get fridaDoctorScriptPath => '$fridaDir/frida_doctor.sh';
  String get fridaCaptureScriptPath => '$fridaDir/run_frida_capture.sh';
  String get decompiledDir => '$artifactsRootDir/decompiled';
  String get mcpDir => '$artifactsRootDir/mcp';
  String get mcpTemplatesPath =>
      '$mcpDir/openhand_android_reverse_mcp_templates.json';
  String get mcpReadmePath => '$mcpDir/README.md';
  String get mcpSetupGuidePath => '$mcpDir/SETUP.md';
  String get logcatDir => '$artifactsRootDir/logcat';
  String get networkDir => '$artifactsRootDir/network';
  String get mitmproxyAddonPath => '$networkDir/openhand_mitm_jsonl.py';
  String get networkReadmePath => '$networkDir/README.md';
  String get networkProxyProbeScriptPath => '$networkDir/proxy_probe.sh';
  String get certsDir => '$artifactsRootDir/certs';
  String get certsReadmePath => '$certsDir/README.md';
  String get networkSecurityConfigPath =>
      '$certsDir/res/xml/network_security_config.xml';
  String get manifestNetworkConfigSnippetPath =>
      '$certsDir/AndroidManifest.application.xml';
  String get installMitmCaRootScriptPath => '$certsDir/install_mitm_ca_root.sh';
  String get generateDebugKeystoreScriptPath =>
      '$certsDir/generate_debug_keystore.sh';
  String get signRepackedApkScriptPath => '$certsDir/sign_repacked_apk.sh';
  String get verifyApkSignatureScriptPath =>
      '$certsDir/verify_apk_signature.sh';
  String get scriptsDir => '$artifactsRootDir/scripts';
  String get scriptsReadmePath => '$scriptsDir/README.md';
  String get adbOneShotScriptPath => '$scriptsDir/adb_one_shot.sh';
  String get dynamicProbeScriptPath => '$scriptsDir/android_dynamic_probe.sh';
  String get reproducePythonPath => '$scriptsDir/reproduce_http.py';
  String get reproduceCurlPath => '$scriptsDir/reproduce_curl.sh';
  String get evidenceBundleScriptPath => '$scriptsDir/make_evidence_bundle.sh';
  String get toolchainDir => '$artifactsRootDir/toolchain';
  String get toolchainReadmePath => '$toolchainDir/README.md';
  String get toolchainSetupCommandsPath => '$toolchainDir/setup_commands.json';
  String get logsDir => '$artifactsRootDir/logs';

  final AndroidReverseAdbClient _adbClient;

  AndroidReverseSessionState _state = AndroidReverseSessionState.idle;
  AndroidReverseSessionState get state => _state;

  AdbDevice? _connectedDevice;
  AdbDevice? get connectedDevice => _connectedDevice;

  List<AdbDevice> _allDevices = const <AdbDevice>[];
  List<AdbDevice> get allDevices => _allDevices;

  List<AndroidProcess> _processes = const <AndroidProcess>[];
  List<AndroidProcess> get processes => _processes;

  String? _lastStaticQuickScanDir;
  String? get lastStaticQuickScanDir => _lastStaticQuickScanDir;

  AdbCommandResult? _lastStaticQuickScanResult;
  AdbCommandResult? get lastStaticQuickScanResult => _lastStaticQuickScanResult;

  Process? _networkCaptureProcess;
  int? get networkCapturePid => _networkCaptureProcess?.pid;
  bool get networkCaptureRunning => _networkCaptureProcess != null;

  DateTime? _networkCaptureStartedAt;

  final BoundedLogBuffer _networkCaptureStdout = BoundedLogBuffer(
    maxCharacters: _kNetworkCaptureTranscriptMaxChars,
  );
  final BoundedLogBuffer _networkCaptureStderr = BoundedLogBuffer(
    maxCharacters: _kNetworkCaptureTranscriptMaxChars,
  );

  String get networkCaptureTranscript {
    final buffer = StringBuffer();
    final process = _networkCaptureProcess;
    if (process != null) {
      buffer
        ..writeln('mitmdump_pid=${process.pid}')
        ..writeln(
          'started_at=${_networkCaptureStartedAt?.toUtc().toIso8601String() ?? "-"}',
        );
    } else {
      buffer.writeln('mitmdump_pid=-');
    }
    final stdoutText = _networkCaptureStdout.snapshot().join().trim();
    final stderrText = _networkCaptureStderr.snapshot().join().trim();
    if (stdoutText.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('[stdout]')
        ..writeln(stdoutText);
    }
    if (stderrText.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('[stderr]')
        ..writeln(stderrText);
    }
    return buffer.toString().trimRight();
  }

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _disposed = false;
  bool _notifierDisposed = false;
  Timer? _watchdogTimer;
  StreamSubscription<String>? _networkCaptureStdoutSub;
  StreamSubscription<String>? _networkCaptureStderrSub;
  Future<AdbCommandResult>? _networkCaptureStartFuture;
  Future<void>? _networkCaptureStopFuture;
  int _networkCaptureGeneration = 0;
  Future<void>? _startFuture;
  Future<void>? _stopFuture;
  Future<void>? _deviceRefreshFuture;
  Future<void>? _shutdownFuture;
  bool _deviceRefreshQueued = false;
  int _processRefreshGeneration = 0;

  bool get isRunning =>
      _state == AndroidReverseSessionState.running ||
      _state == AndroidReverseSessionState.deviceLost;

  void clearErrorMessage() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _safeNotify();
  }

  Future<void> start() {
    if (_disposed || isRunning) {
      return Future<void>.value();
    }
    final stopping = _stopFuture;
    if (stopping != null) {
      return stopping.then((_) => start());
    }
    final active = _startFuture;
    if (active != null) return active;
    if (_state == AndroidReverseSessionState.stopped) {
      _state = AndroidReverseSessionState.idle;
    }
    late final Future<void> starting;
    starting = _startOnce().whenComplete(() {
      if (identical(_startFuture, starting)) {
        _startFuture = null;
      }
    });
    _startFuture = starting;
    return starting;
  }

  Future<void> _startOnce() async {
    if (_disposed || _state != AndroidReverseSessionState.idle) return;
    await _ensureArtifactDirectories();
    await _writeMcpLinkageArtifacts(updateError: false);
    if (_state == AndroidReverseSessionState.stopped || _disposed) return;
    await _warmStaticQuickScanFromConfig();
    if (_state == AndroidReverseSessionState.stopped || _disposed) return;
    await _refreshDevices();
    if (_state == AndroidReverseSessionState.stopped || _disposed) return;
    _state = AndroidReverseSessionState.running;
    _watchdogTimer?.cancel();
    _watchdogTimer = startNonOverlappingPeriodicTimer(
      _kDeviceWatchdogInterval,
      (_) => _refreshDevices(),
    );
    _safeNotify();
  }

  Future<void> stop() {
    final active = _stopFuture;
    if (active != null) return active;
    late final Future<void> stopping;
    stopping = _stopOnce().whenComplete(() {
      if (identical(_stopFuture, stopping)) {
        _stopFuture = null;
      }
    });
    _stopFuture = stopping;
    return stopping;
  }

  Future<void> _stopOnce() async {
    _networkCaptureGeneration += 1;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _state = AndroidReverseSessionState.stopped;
    final starting = _startFuture;
    if (starting != null) {
      await runAsyncCleanupBounded(
        () => starting,
        timeout: _kRuntimeCleanupTimeout,
        onError: (error, stack) => silentLog(_kTag, '停止时等待会话启动', error, stack),
      );
    }
    await _stopNetworkCaptureResources();
    _safeNotify();
  }

  /// 停止计时器、流订阅和已登记的 mitmdump 进程。
  /// 重复调用共享同一个有界清理任务。
  Future<void> shutdown() {
    final active = _shutdownFuture;
    if (active != null) return active;
    _disposed = true;
    _networkCaptureGeneration += 1;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _state = AndroidReverseSessionState.stopped;
    final shutdown =
        () async {
          final startingSession = _startFuture;
          final stoppingSession = _stopFuture;
          final startingCapture = _networkCaptureStartFuture;
          final refreshing = _deviceRefreshFuture;
          await Future.wait<bool>(<Future<bool>>[
            if (startingSession != null)
              runAsyncCleanupBounded(
                () => startingSession,
                timeout: _kRuntimeCleanupTimeout,
                onError: (error, stack) =>
                    silentLog(_kTag, '等待会话启动', error, stack),
              ),
            if (stoppingSession != null)
              runAsyncCleanupBounded(
                () => stoppingSession,
                timeout: _kRuntimeCleanupTimeout,
                onError: (error, stack) =>
                    silentLog(_kTag, '等待会话停止', error, stack),
              ),
            if (startingCapture != null)
              runAsyncCleanupBounded(
                () => startingCapture,
                timeout: _kRuntimeCleanupTimeout,
                onError: (error, stack) =>
                    silentLog(_kTag, '等待网络捕获启动', error, stack),
              ),
            if (refreshing != null)
              runAsyncCleanupBounded(
                () => refreshing,
                timeout: _kRuntimeCleanupTimeout,
                onError: (error, stack) =>
                    silentLog(_kTag, '等待设备刷新', error, stack),
              ),
          ]);
          await _stopNetworkCaptureResources();
        }().catchError((Object error, StackTrace stack) {
          silentLog(_kTag, '关闭 Android 逆向会话', error, stack);
        });
    _shutdownFuture = shutdown;
    return shutdown;
  }

  @override
  void dispose() {
    if (_notifierDisposed) return;
    _notifierDisposed = true;
    unawaited(shutdown());
    super.dispose();
  }

  // ── 公开操作接口 ───────────────────────────────────────────────────────

  Future<List<AdbDevice>> refreshDevices() async {
    await _refreshDevices();
    return _allDevices;
  }

  Future<List<AndroidProcess>> refreshProcesses({
    String? filterName,
    String? serial,
  }) async {
    final generation = ++_processRefreshGeneration;
    try {
      final procs = await _clientForSerial(
        serial,
      ).listProcesses(filterName: filterName);
      final snapshot = List<AndroidProcess>.unmodifiable(procs);
      if (!_disposed && generation == _processRefreshGeneration) {
        _processes = snapshot;
        _safeNotify();
      }
      return snapshot;
    } catch (e, st) {
      silentLog(_kTag, '刷新进程列表失败', e, st);
      if (!_disposed && generation == _processRefreshGeneration) {
        _processes = const <AndroidProcess>[];
        _safeNotify();
      }
      return const <AndroidProcess>[];
    }
  }

  AndroidReverseAdbClient _clientForSerial(String? serial) {
    final normalizedSerial = serial?.trim();
    if (normalizedSerial == null ||
        normalizedSerial.isEmpty ||
        normalizedSerial == _adbClient.deviceSerial) {
      return _adbClient;
    }
    return AndroidReverseAdbClient(
      adbPath: _adbClient.adbPath,
      deviceSerial: normalizedSerial,
    );
  }

  Future<List<String>> listPackages({bool thirdParty = true, String? serial}) =>
      _clientForSerial(serial).listPackages(thirdParty: thirdParty);

  Future<String?> getPackagePath(String packageName, {String? serial}) =>
      _clientForSerial(serial).getPackagePath(packageName);

  Future<List<String>> getPackagePaths(String packageName, {String? serial}) =>
      _clientForSerial(serial).getPackagePaths(packageName);

  Future<String?> getPackageVersion(String packageName, {String? serial}) =>
      _clientForSerial(serial).getPackageVersion(packageName);

  Future<AdbCommandResult> capturePackageReportToArtifacts(
    String packageName, {
    String? serial,
  }) async {
    final normalizedPackage = packageName.trim();
    if (!looksLikeAndroidPackageName(normalizedPackage)) {
      return AdbCommandResult(
        args: const <String>['package-report', '<invalid-package>'],
        exitCode: -1,
        stdout: '',
        stderr: 'Android 包名无效：$packageName',
      );
    }
    final client = _clientForSerial(serial);
    final targetDir = Directory(
      '$packagesDir/${_safeArtifactName(normalizedPackage)}',
    );
    final stamp = _artifactTimestamp();
    final markdownPath = '${targetDir.path}/package_report_$stamp.md';
    final jsonPath = '${targetDir.path}/package_report_$stamp.json';
    try {
      await createDirectoryBounded(targetDir);
      final pathsFuture = client.getPackagePaths(normalizedPackage);
      final versionFuture = client.getPackageVersion(normalizedPackage);
      final launcherFuture = client.resolveLauncherActivity(normalizedPackage);
      final dumpsysFuture = client.shellDetailed(
        'dumpsys package $normalizedPackage',
        timeout: _kPackageReportTimeout,
      );
      final paths = await pathsFuture;
      final version = await versionFuture;
      final launcher = await launcherFuture;
      final dumpsys = await dumpsysFuture;
      final summary = _packageDumpsysSummary(dumpsys.stdout);
      final capturedAt = DateTime.now().toUtc().toIso8601String();
      final json = <String, Object?>{
        'captured_at': capturedAt,
        if (serial?.trim().isNotEmpty ?? false) 'device_serial': serial!.trim(),
        'package_name': normalizedPackage,
        'apk_paths': paths,
        'version': version,
        'launcher_activity': launcher,
        'dumpsys': <String, Object?>{
          'summary': summary,
          'exit_code': dumpsys.exitCode,
          'timed_out': dumpsys.timedOut,
          'stderr': dumpsys.stderr,
        },
      };
      final markdown = _packageReportMarkdown(
        capturedAt: capturedAt,
        packageName: normalizedPackage,
        paths: paths,
        version: version,
        launcher: launcher,
        dumpsys: dumpsys,
        summary: summary,
        jsonPath: jsonPath,
      );
      await Future.wait(<Future<void>>[
        writeFileAtomically(File(markdownPath), markdown),
        writeFileAtomically(File(jsonPath), prettyPrintJson(json)),
      ]);
      return AdbCommandResult(
        args: <String>['package-report', normalizedPackage],
        exitCode: dumpsys.exitCode,
        stdout: <String>[
          '软件包报告：$markdownPath',
          '软件包报告 JSON：$jsonPath',
          if (paths.isNotEmpty) 'APK 路径：${paths.join(', ')}',
          if (launcher != null && launcher.isNotEmpty) '启动 Activity：$launcher',
        ].join('\n'),
        stderr: dumpsys.stderr,
        timedOut: dumpsys.timedOut,
      );
    } catch (e, st) {
      silentLog(_kTag, '捕获软件包报告到产物目录失败', e, st);
      return AdbCommandResult(
        args: <String>['package-report', normalizedPackage],
        exitCode: -1,
        stdout: '',
        stderr: '$e',
      );
    }
  }

  Future<String?> resolveLauncherActivity(
    String packageName, {
    String? serial,
  }) => _clientForSerial(serial).resolveLauncherActivity(packageName);

  Future<String?> logcat({
    String? tag,
    String? level,
    int lines = 200,
    String? serial,
  }) => _clientForSerial(serial).logcat(tag: tag, level: level, lines: lines);

  Future<AdbCommandResult> logcatDetailed({
    String? tag,
    String? level,
    int lines = 200,
    String? pid,
    String? serial,
  }) => _clientForSerial(
    serial,
  ).logcatDetailed(tag: tag, level: level, lines: lines, pid: pid);

  Future<AdbCommandResult> clearLogcatDetailed({String? serial}) =>
      _clientForSerial(serial).clearLogcatDetailed();

  Future<AdbCommandResult> captureLogcatSnapshotToArtifacts({
    String? tag,
    String? level,
    String? pid,
    String? packageName,
    String? serial,
    int lines = 500,
  }) async {
    final stamp = _artifactTimestamp();
    final txtPath = '$logcatDir/logcat_snapshot_$stamp.txt';
    final jsonPath = '$logcatDir/logcat_snapshot_$stamp.json';
    try {
      await createDirectoryBounded(Directory(logcatDir));
      final result = await logcatDetailed(
        tag: tag,
        level: level,
        lines: lines,
        pid: pid,
        serial: serial,
      );
      final capturedAt = DateTime.now().toUtc().toIso8601String();
      final text = result.stdout.trimRight();
      final json = <String, Object?>{
        'captured_at': capturedAt,
        if (serial?.trim().isNotEmpty ?? false) 'device_serial': serial!.trim(),
        if (tag?.trim().isNotEmpty ?? false) 'tag': tag!.trim(),
        if (level?.trim().isNotEmpty ?? false)
          'level_filter': level!.trim().toUpperCase(),
        if (pid?.trim().isNotEmpty ?? false) 'pid': pid!.trim(),
        if (packageName?.trim().isNotEmpty ?? false)
          'package_name': packageName!.trim(),
        'lines_requested': lines,
        'stdout_line_count': text.isEmpty ? 0 : text.split('\n').length,
        'exit_code': result.exitCode,
        'timed_out': result.timedOut,
        'stderr': result.stderr,
        'text_path': txtPath,
      };
      await Future.wait(<Future<void>>[
        writeFileAtomically(File(txtPath), text.isEmpty ? '（空）\n' : '$text\n'),
        writeFileAtomically(File(jsonPath), prettyPrintJson(json)),
      ]);
      return AdbCommandResult(
        args: <String>['logcat-snapshot'],
        exitCode: result.exitCode,
        stdout: <String>[
          'Logcat 快照：$txtPath',
          'Logcat 快照 JSON：$jsonPath',
          if (text.isNotEmpty) '捕获行数：${text.split('\n').length}',
        ].join('\n'),
        stderr: result.stderr,
        timedOut: result.timedOut,
      );
    } catch (e, st) {
      silentLog(_kTag, '捕获 Logcat 快照到产物目录失败', e, st);
      return AdbCommandResult(
        args: const <String>['logcat-snapshot'],
        exitCode: -1,
        stdout: '',
        stderr: '$e',
      );
    }
  }

  Future<String?> shell(String command, {String? serial}) =>
      _clientForSerial(serial).shell(command);

  Future<AdbCommandResult> shellDetailed(
    String command, {
    String? serial,
    Duration? timeout,
  }) => _clientForSerial(serial).shellDetailed(command, timeout: timeout);

  Future<AdbCommandResult> forceStopAppDetailed(
    String packageName, {
    String? serial,
  }) => _clientForSerial(serial).forceStopAppDetailed(packageName);

  Future<AdbCommandResult> clearPackageDataDetailed(
    String packageName, {
    String? serial,
  }) => _clientForSerial(serial).clearPackageDataDetailed(packageName);

  Future<AdbCommandResult> uninstallPackageDetailed(
    String packageName, {
    String? serial,
    bool keepData = false,
  }) => _clientForSerial(
    serial,
  ).uninstallPackageDetailed(packageName, keepData: keepData);

  Future<AdbCommandResult> startPackageDetailed(
    String packageName, {
    String? serial,
  }) => _clientForSerial(serial).startPackageDetailed(packageName);

  Future<String?> pidOfPackage(String packageName, {String? serial}) =>
      _clientForSerial(serial).pidOfPackage(packageName);

  Future<AndroidPackagePidLookupResult> pidOfPackageDetailed(
    String packageName, {
    String? serial,
  }) => _clientForSerial(serial).pidOfPackageDetailed(packageName);

  Future<AdbCommandResult> killProcessDetailed(int pid, {String? serial}) =>
      _clientForSerial(serial).killProcessDetailed(pid);

  Future<AdbCommandResult> installApkDetailed(
    String localApkPath, {
    String? serial,
    bool grantRuntimePermissions = true,
  }) => _clientForSerial(serial).installApkDetailed(
    localApkPath,
    grantRuntimePermissions: grantRuntimePermissions,
  );

  Future<AdbCommandResult> pushDetailed(
    String localPath,
    String remotePath, {
    String? serial,
  }) => _clientForSerial(serial).pushDetailed(localPath, remotePath);

  Future<AdbCommandResult> pullDetailed(
    String remotePath,
    String localPath, {
    String? serial,
  }) => _clientForSerial(serial).pullDetailed(remotePath, localPath);

  Future<Map<String, String>> getProperties({String? serial}) =>
      _clientForSerial(serial).getProperties();

  Future<bool> forwardPort(int local, int remote, {String? serial}) =>
      _clientForSerial(serial).forwardPort(local, remote);

  Future<bool> removeForward(int local, {String? serial}) =>
      _clientForSerial(serial).removeForward(local);

  Future<AdbCommandResult> forwardPortDetailed(
    int local,
    int remote, {
    String? serial,
  }) => _clientForSerial(serial).forwardPortDetailed(local, remote);

  Future<AdbCommandResult> removeForwardDetailed(int local, {String? serial}) =>
      _clientForSerial(serial).removeForwardDetailed(local);

  Future<String?> listForwards({String? serial}) =>
      _clientForSerial(serial).listForwards();

  Future<bool> removeAllForwards({String? serial}) =>
      _clientForSerial(serial).removeAllForwards();

  Future<bool> reversePort(int devicePort, int hostPort, {String? serial}) =>
      _clientForSerial(serial).reversePort(devicePort, hostPort);

  Future<bool> removeReverse(int devicePort, {String? serial}) =>
      _clientForSerial(serial).removeReverse(devicePort);

  Future<AdbCommandResult> reversePortDetailed(
    int devicePort,
    int hostPort, {
    String? serial,
  }) => _clientForSerial(serial).reversePortDetailed(devicePort, hostPort);

  Future<AdbCommandResult> removeReverseDetailed(
    int devicePort, {
    String? serial,
  }) => _clientForSerial(serial).removeReverseDetailed(devicePort);

  Future<String?> listReverses({String? serial}) =>
      _clientForSerial(serial).listReverses();

  Future<bool> removeAllReverses({String? serial}) =>
      _clientForSerial(serial).removeAllReverses();

  Future<AdbCommandResult> saveFridaScriptToArtifacts({
    required String script,
    String? presetAssetPath,
    String? packageName,
  }) async {
    final normalizedScript = script.trimRight();
    if (normalizedScript.trim().isEmpty) {
      return const AdbCommandResult(
        args: <String>['frida-script-save', '<empty>'],
        exitCode: -1,
        stdout: '',
        stderr: 'Frida 脚本为空。',
      );
    }
    final target = _safeArtifactName(
      _firstNonEmpty(<String?>[packageName, config.packageName, 'generic']),
    );
    final presetName = (presetAssetPath ?? 'custom_script')
        .split('/')
        .last
        .replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
    final preset = _safeArtifactName(presetName);
    final stamp = _artifactTimestamp();
    final scriptPath = '$fridaScriptsDir/${target}_${preset}_$stamp.js';
    final jsonPath = '$fridaScriptsDir/${target}_${preset}_$stamp.json';
    try {
      await createDirectoryBounded(Directory(fridaScriptsDir));
      final capturedAt = DateTime.now().toUtc().toIso8601String();
      final metadata = <String, Object?>{
        'captured_at': capturedAt,
        if (packageName?.trim().isNotEmpty ?? false)
          'package_name': packageName!.trim(),
        if (presetAssetPath?.trim().isNotEmpty ?? false)
          'preset_asset_path': presetAssetPath!.trim(),
        'script_path': scriptPath,
        'char_count': normalizedScript.length,
        'line_count': normalizedScript.split('\n').length,
      };
      await Future.wait(<Future<void>>[
        writeFileAtomically(File(scriptPath), '$normalizedScript\n'),
        writeFileAtomically(File(jsonPath), prettyPrintJson(metadata)),
      ]);
      return AdbCommandResult(
        args: const <String>['frida-script-save'],
        exitCode: 0,
        stdout: <String>[
          'Frida 脚本：$scriptPath',
          'Frida 脚本元数据：$jsonPath',
        ].join('\n'),
        stderr: '',
      );
    } catch (e, st) {
      silentLog(_kTag, '保存 Frida 脚本到产物目录失败', e, st);
      return AdbCommandResult(
        args: const <String>['frida-script-save'],
        exitCode: -1,
        stdout: '',
        stderr: '$e',
      );
    }
  }

  Future<AdbCommandResult> connect(String endpoint) =>
      _adbClient.connect(endpoint);

  Future<AdbCommandResult> disconnect([String? endpoint]) =>
      _adbClient.disconnect(endpoint);

  Future<AdbCommandResult> reboot({String? serial, String? mode}) =>
      _clientForSerial(serial).reboot(mode);

  Future<AdbCommandResult> root({String? serial}) =>
      _clientForSerial(serial).root();

  Future<AdbCommandResult> remount({String? serial}) =>
      _clientForSerial(serial).remount();

  Future<AdbCommandResult> tcpip(int port, {String? serial}) =>
      _clientForSerial(serial).tcpip(port);

  Future<AdbCommandResult> captureScreenshotToArtifacts({
    String? serial,
  }) async {
    final client = _clientForSerial(serial);
    final stamp = _artifactTimestamp();
    final remotePath = '$kAndroidScreenshotDir/$stamp.png';
    final localPath = '$screenshotsDir/$stamp.png';
    await createDirectoryBounded(Directory(screenshotsDir));
    final capture = await client.captureScreenshotDetailed(remotePath);
    if (!capture.ok && !capture.hasUsableStdout) return capture;
    final pull = await client.pullDetailed(remotePath, localPath);
    return _combineAdbResults(<AdbCommandResult>[capture, pull]);
  }

  Future<AdbCommandResult> screenRecordToArtifacts({
    String? serial,
    int seconds = 10,
  }) async {
    final client = _clientForSerial(serial);
    final stamp = _artifactTimestamp();
    final remotePath = '$kAndroidRecordingDir/$stamp.mp4';
    final localPath = '$recordingsDir/$stamp.mp4';
    await createDirectoryBounded(Directory(recordingsDir));
    final record = await client.screenRecordDetailed(
      remotePath,
      seconds: seconds,
    );
    if (!record.ok && !record.hasUsableStdout) return record;
    final pull = await client.pullDetailed(remotePath, localPath);
    return _combineAdbResults(<AdbCommandResult>[record, pull]);
  }

  Future<AdbCommandResult> captureDeviceReportToArtifacts({
    String? serial,
  }) async {
    final normalizedSerial = serial?.trim();
    final client = _clientForSerial(normalizedSerial);
    final reportSerial = normalizedSerial == null || normalizedSerial.isEmpty
        ? 'default'
        : normalizedSerial;
    final targetDir = Directory(
      '$devicesDir/${_safeArtifactName(reportSerial)}',
    );
    final stamp = _artifactTimestamp();
    final markdownPath = '${targetDir.path}/device_report_$stamp.md';
    final jsonPath = '${targetDir.path}/device_report_$stamp.json';
    try {
      await createDirectoryBounded(targetDir);
      final devices = await _adbClient.listDevices();
      final propsFuture = client.getProperties();
      final forwardsFuture = client.listForwards();
      final reversesFuture = client.listReverses();
      final snapshotFuture = client.shellDetailed(
        _deviceReportSnapshotScript,
        timeout: _kDeviceReportTimeout,
      );
      final logcatFuture = client.logcatDetailed(lines: 80);
      final packageName = config.packageName?.trim();
      final launcherFuture = packageName == null || packageName.isEmpty
          ? Future<String?>.value()
          : client.resolveLauncherActivity(packageName);
      final props = await propsFuture;
      final forwards = await forwardsFuture;
      final reverses = await reversesFuture;
      final snapshot = await snapshotFuture;
      final logcat = await logcatFuture;
      final launcher = await launcherFuture;
      final capturedAt = DateTime.now().toUtc().toIso8601String();
      final json = <String, Object?>{
        'captured_at': capturedAt,
        'serial': reportSerial,
        'devices': devices
            .map(
              (device) => <String, Object?>{
                'serial': device.serial,
                'state': device.state,
                'model': device.model,
                'product': device.product,
                'transport_id': device.transportId,
              },
            )
            .toList(growable: false),
        'properties': props,
        'forwards': splitTrimmedNonEmpty(forwards ?? '', separator: '\n'),
        'reverses': splitTrimmedNonEmpty(reverses ?? '', separator: '\n'),
        'target_package': packageName,
        'launcher_activity': launcher,
        'snapshot': <String, Object?>{
          'stdout': snapshot.stdout,
          'stderr': snapshot.stderr,
          'exit_code': snapshot.exitCode,
          'timed_out': snapshot.timedOut,
        },
        'logcat_tail': <String, Object?>{
          'stdout': logcat.stdout,
          'stderr': logcat.stderr,
          'exit_code': logcat.exitCode,
          'timed_out': logcat.timedOut,
        },
      };
      final markdown = _deviceReportMarkdown(
        capturedAt: capturedAt,
        serial: reportSerial,
        devices: devices,
        props: props,
        forwards: forwards,
        reverses: reverses,
        packageName: packageName,
        launcher: launcher,
        snapshot: snapshot,
        logcat: logcat,
        jsonPath: jsonPath,
      );
      await Future.wait(<Future<void>>[
        writeFileAtomically(File(markdownPath), markdown),
        writeFileAtomically(File(jsonPath), prettyPrintJson(json)),
      ]);
      return AdbCommandResult(
        args: <String>['device-report', reportSerial],
        exitCode: 0,
        stdout: <String>[
          '设备报告：$markdownPath',
          '设备报告 JSON：$jsonPath',
          if (launcher != null && launcher.isNotEmpty) '启动 Activity：$launcher',
        ].join('\n'),
        stderr: <String>[
          if (snapshot.stderr.trim().isNotEmpty) snapshot.stderr.trim(),
          if (logcat.stderr.trim().isNotEmpty) logcat.stderr.trim(),
        ].join('\n'),
        timedOut: snapshot.timedOut || logcat.timedOut,
      );
    } catch (e, st) {
      silentLog(_kTag, '捕获设备报告到产物目录失败', e, st);
      return AdbCommandResult(
        args: <String>['device-report', reportSerial],
        exitCode: -1,
        stdout: '',
        stderr: '$e',
      );
    }
  }

  Future<AdbCommandResult> pullPackageApksDetailed(
    String packageName, {
    String? serial,
  }) async {
    final client = _clientForSerial(serial);
    final packagePaths = await client.getPackagePaths(packageName);
    if (packagePaths.isEmpty) {
      return AdbCommandResult(
        args: const <String>['shell', 'pm path <package>'],
        exitCode: -1,
        stdout: '',
        stderr: '未找到 $packageName 的 APK 路径。',
      );
    }
    final targetDir = Directory('$apksDir/${_safeArtifactName(packageName)}');
    await createDirectoryBounded(targetDir);
    final results = <AdbCommandResult>[];
    for (final remotePath in packagePaths) {
      final name = remotePath.split('/').last.trim();
      final localPath = '${targetDir.path}/${name.isEmpty ? 'base.apk' : name}';
      results.add(await client.pullDetailed(remotePath, localPath));
    }
    return _combineAdbResults(results);
  }

  Future<AdbCommandResult> runStaticQuickScan({
    String? apkPath,
    String? packageName,
    Duration timeout = _kStaticQuickScanTimeout,
  }) async {
    if (Platform.isWindows) {
      return const AdbCommandResult(
        args: <String>['static-quick-scan'],
        exitCode: -1,
        stdout: '',
        stderr: '静态快速扫描需要 /bin/sh。',
      );
    }
    final rawApkPath = (apkPath ?? config.apkPath ?? '').trim();
    if (rawApkPath.isEmpty) {
      return const AdbCommandResult(
        args: <String>['static-quick-scan', '<missing-apk>'],
        exitCode: -1,
        stdout: '',
        stderr: '静态快速扫描必须提供 APK 路径。',
      );
    }
    final apkFile = File(rawApkPath);
    if (!await isRegularFilePath(apkFile.path, followLinks: true)) {
      return AdbCommandResult(
        args: <String>['static-quick-scan', rawApkPath],
        exitCode: -1,
        stdout: '',
        stderr: 'APK 文件不存在：$rawApkPath',
      );
    }
    final slug = _safeArtifactName(
      _firstNonEmpty(<String?>[
        packageName,
        config.packageName,
        _basenameWithoutExtension(rawApkPath),
      ]),
    );
    final outputDir = Directory('$decompiledDir/$slug/quick_scan');
    await createDirectoryBounded(outputDir);
    final sw = Stopwatch()..start();
    final result = await runTrackedProcessOrFailed(
      '/bin/sh',
      <String>['-lc', _staticQuickScanScript],
      timeout: timeout,
      tag: 'android_reverse.static_quick_scan',
      environment: <String, String>{
        'APK_PATH': rawApkPath,
        'OUT_DIR': outputDir.path,
      },
    );
    sw.stop();
    final timedOut =
        result.exitCode == -1 &&
        sw.elapsed + _kStaticQuickScanTimeoutSkew >= timeout;
    final summary = await _staticQuickScanSummary(
      outputDir,
      result,
      timedOut: timedOut,
    );
    final commandResult = AdbCommandResult(
      args: <String>['static-quick-scan', rawApkPath],
      exitCode: result.exitCode,
      stdout: summary,
      stderr: result.stderr.toString(),
      timedOut: timedOut,
    );
    _lastStaticQuickScanDir = outputDir.path;
    _lastStaticQuickScanResult = commandResult;
    _safeNotify();
    return commandResult;
  }

  Future<String> ensureMitmproxyJsonlAddon() async {
    try {
      await createDirectoryBounded(Directory(networkDir));
      await File(
        networkJsonlPath,
      ).create(recursive: true).timeout(_kArtifactFileOperationTimeout);
      final file = File(mitmproxyAddonPath);
      await Future.wait(<Future<void>>[
        writeFileAtomically(file, _mitmproxyJsonlAddon),
        writeFileAtomically(File(networkReadmePath), _networkCaptureReadme),
        writeFileAtomically(
          File(networkProxyProbeScriptPath),
          _networkProxyProbeScript,
        ),
      ]);
      if (!Platform.isWindows) {
        await runTrackedProcessOrFailed(
          _kAndroidReverseChmodExecutable,
          <String>['+x', networkProxyProbeScriptPath],
          timeout: _kArtifactChmodTimeout,
          tag: 'android_reverse.network_probe_chmod',
        );
      }
      return file.path;
    } catch (e, stack) {
      silentLog(_kTag, '网络代理探测脚本准备', e, stack);
      _errorMessage = '$e';
      _safeNotify();
      rethrow;
    }
  }

  Future<String> ensureCertificateArtifacts({String? packageName}) async {
    try {
      final pkg = packageName?.trim();
      await Future.wait(<Future<void>>[
        writeFileAtomically(
          File(networkSecurityConfigPath),
          _networkSecurityConfigXml,
        ),
        writeFileAtomically(
          File(manifestNetworkConfigSnippetPath),
          _manifestNetworkConfigSnippet,
        ),
        writeFileAtomically(
          File(installMitmCaRootScriptPath),
          _installMitmCaRootScript,
        ),
        writeFileAtomically(
          File(generateDebugKeystoreScriptPath),
          _generateDebugKeystoreScript,
        ),
        writeFileAtomically(
          File(signRepackedApkScriptPath),
          _signRepackedApkScript,
        ),
        writeFileAtomically(
          File(verifyApkSignatureScriptPath),
          _verifyApkSignatureScript,
        ),
        writeFileAtomically(File(certsReadmePath), _certificateReadme(pkg)),
      ]);
      if (!Platform.isWindows) {
        await runTrackedProcessOrFailed(
          _kAndroidReverseChmodExecutable,
          <String>[
            '+x',
            installMitmCaRootScriptPath,
            generateDebugKeystoreScriptPath,
            signRepackedApkScriptPath,
            verifyApkSignatureScriptPath,
          ],
          timeout: _kArtifactChmodTimeout,
          tag: 'android_reverse.certs_chmod',
        );
      }
      return <String>[
        '证书产物：$certsDir',
        'network_security_config: $networkSecurityConfigPath',
        'manifest_snippet: $manifestNetworkConfigSnippetPath',
        'root_ca_install_script: $installMitmCaRootScriptPath',
        'generate_debug_keystore: $generateDebugKeystoreScriptPath',
        'sign_repacked_apk: $signRepackedApkScriptPath',
        'verify_apk_signature: $verifyApkSignatureScriptPath',
        'readme: $certsReadmePath',
      ].join('\n');
    } catch (e, stack) {
      silentLog(_kTag, '证书与脚本准备', e, stack);
      _errorMessage = '$e';
      _safeNotify();
      rethrow;
    }
  }

  Future<String> ensureMcpLinkageArtifacts() =>
      _writeMcpLinkageArtifacts(updateError: true);

  Future<AdbCommandResult> makeEvidenceBundleToArtifacts() async {
    if (Platform.isWindows) {
      return const AdbCommandResult(
        args: <String>['evidence-bundle'],
        exitCode: -1,
        stdout: '',
        stderr: '生成证据包需要 bash。',
        displayCommand: _kEvidenceBundleDisplayCommand,
      );
    }
    try {
      if (!await isRegularFilePath(
        evidenceBundleScriptPath,
        followLinks: true,
      )) {
        await _writeMcpLinkageArtifacts(updateError: true);
      }
      final result = await runTrackedProcessOrFailed(
        _kAndroidReverseBashExecutable,
        <String>[evidenceBundleScriptPath],
        timeout: _kEvidenceBundleTimeout,
        tag: 'android_reverse.evidence_bundle',
      );
      final stdoutText = result.stdout.toString();
      final stderrText = result.stderr.toString();
      final failedWithoutOutput =
          result.exitCode == -1 &&
          stdoutText.trim().isEmpty &&
          stderrText.trim().isEmpty;
      return AdbCommandResult(
        args: const <String>['evidence-bundle'],
        exitCode: result.exitCode,
        stdout: stdoutText,
        stderr: failedWithoutOutput
            ? '证据包命令执行超时，或未能在 ${_kEvidenceBundleTimeout.inSeconds} 秒内启动。'
            : stderrText,
        timedOut: failedWithoutOutput,
        displayCommand:
            '$_kAndroidReverseBashExecutable $evidenceBundleScriptPath',
      );
    } catch (e, st) {
      silentLog(_kTag, '生成证据包到产物目录失败', e, st);
      return AdbCommandResult(
        args: const <String>['evidence-bundle'],
        exitCode: -1,
        stdout: '',
        stderr: '$e',
        displayCommand: _kEvidenceBundleDisplayCommand,
      );
    }
  }

  Future<AdbCommandResult> runLocalArtifactScriptDetailed({
    required String scriptPath,
    List<String> args = const <String>[],
    Map<String, String> environment = const <String, String>{},
    Duration timeout = _kLocalScriptTimeout,
    String? displayCommand,
    String tag = 'android_reverse.local_script',
  }) async {
    if (Platform.isWindows) {
      return AdbCommandResult(
        args: <String>['local-script', scriptPath, ...args],
        exitCode: -1,
        stdout: '',
        stderr: '本地产物脚本需要 bash。',
        displayCommand: displayCommand,
      );
    }
    final script = File(scriptPath);
    if (!await isRegularFilePath(script.path, followLinks: true)) {
      return AdbCommandResult(
        args: <String>['local-script', scriptPath, ...args],
        exitCode: -1,
        stdout: '',
        stderr: '脚本不存在：$scriptPath',
        displayCommand: displayCommand,
      );
    }
    try {
      final result = await runTrackedProcessOrFailed(
        _kAndroidReverseBashExecutable,
        <String>[scriptPath, ...args],
        timeout: timeout,
        tag: tag,
        environment: environment.isEmpty ? null : environment,
      );
      final stdoutText = result.stdout.toString();
      final stderrText = result.stderr.toString();
      final timedOut =
          result.exitCode == -1 &&
          stdoutText.trim().isEmpty &&
          stderrText.trim().isEmpty;
      return AdbCommandResult(
        args: <String>['local-script', scriptPath, ...args],
        exitCode: result.exitCode,
        stdout: stdoutText,
        stderr: timedOut ? '本地脚本执行超过 ${timeout.inSeconds} 秒。' : stderrText,
        timedOut: timedOut,
        displayCommand:
            displayCommand ??
            '$_kAndroidReverseBashExecutable $scriptPath ${args.join(' ')}'
                .trim(),
      );
    } catch (e, st) {
      silentLog(_kTag, '执行本地产物脚本失败', e, st);
      return AdbCommandResult(
        args: <String>['local-script', scriptPath, ...args],
        exitCode: -1,
        stdout: '',
        stderr: '$e',
        displayCommand: displayCommand,
      );
    }
  }

  Future<AdbCommandResult> runLocalShellDetailed({
    required String actionName,
    required String command,
    Map<String, String> environment = const <String, String>{},
    Duration timeout = _kLocalShellActionTimeout,
    String? displayCommand,
    String tag = 'android_reverse.local_shell',
  }) {
    return _runLocalShellDetailed(
      actionName: actionName,
      command: command,
      environment: environment,
      timeout: timeout,
      displayCommand: displayCommand,
      tag: tag,
    );
  }

  Future<AdbCommandResult> startNetworkCapture({
    int port = kDefaultMitmProxyPort,
  }) {
    if (!isRunning) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['network-capture', 'start'],
          exitCode: -1,
          stdout: '',
          stderr: 'Android 逆向运行时未启动。',
          displayCommand: _kNetworkCaptureDisplayCommand,
        ),
      );
    }
    final active = _networkCaptureStartFuture;
    if (active != null) return active;
    final generation = ++_networkCaptureGeneration;
    late final Future<AdbCommandResult> starting;
    starting = _startNetworkCapture(port: port, generation: generation)
        .whenComplete(() {
          if (identical(_networkCaptureStartFuture, starting)) {
            _networkCaptureStartFuture = null;
          }
        });
    _networkCaptureStartFuture = starting;
    return starting;
  }

  bool _canContinueNetworkCaptureStart(int generation) {
    return !_disposed &&
        _state != AndroidReverseSessionState.stopped &&
        generation == _networkCaptureGeneration;
  }

  AdbCommandResult _networkCaptureStartCancelledResult() {
    return const AdbCommandResult(
      args: <String>['network-capture', 'start'],
      exitCode: -1,
      stdout: '',
      stderr: '网络捕获启动已取消。',
      displayCommand: _kNetworkCaptureDisplayCommand,
    );
  }

  Future<AdbCommandResult> _startNetworkCapture({
    required int port,
    required int generation,
  }) async {
    final stopping = _networkCaptureStopFuture;
    if (stopping != null) await stopping;
    if (!_canContinueNetworkCaptureStart(generation)) {
      return _networkCaptureStartCancelledResult();
    }
    if (!isValidTcpPort(port)) {
      return AdbCommandResult(
        args: <String>['network-capture', 'start'],
        exitCode: -1,
        stdout: '',
        stderr: '代理端口无效：$port',
        displayCommand: _kNetworkCaptureDisplayCommand,
      );
    }
    if (_networkCaptureProcess != null) {
      return AdbCommandResult(
        args: <String>['network-capture', 'start'],
        exitCode: 0,
        stdout: networkCaptureTranscript,
        stderr: 'mitmdump 已在运行。',
        displayCommand: _kNetworkCaptureDisplayCommand,
      );
    }
    if (Platform.isWindows) {
      return const AdbCommandResult(
        args: <String>['network-capture', 'start'],
        exitCode: -1,
        stdout: '',
        stderr: 'mitmdump 捕获需要 POSIX Shell 环境。',
        displayCommand: _kNetworkCaptureDisplayCommand,
      );
    }
    Process? startedProcess;
    try {
      final mitmdump = await _resolveLocalExecutable('mitmdump');
      if (!_canContinueNetworkCaptureStart(generation)) {
        return _networkCaptureStartCancelledResult();
      }
      if (mitmdump == null) {
        return const AdbCommandResult(
          args: <String>['network-capture', 'start'],
          exitCode: 127,
          stdout: '',
          stderr: '未找到 mitmdump，请先安装 mitmproxy。',
          displayCommand: 'mitmdump',
        );
      }
      final addonPath = await ensureMitmproxyJsonlAddon();
      if (!_canContinueNetworkCaptureStart(generation)) {
        return _networkCaptureStartCancelledResult();
      }
      await createDirectoryBounded(Directory(networkDir));
      await File(
        networkJsonlPath,
      ).create(recursive: true).timeout(_kArtifactFileOperationTimeout);
      if (!_canContinueNetworkCaptureStart(generation)) {
        return _networkCaptureStartCancelledResult();
      }
      _networkCaptureStdout.clear();
      _networkCaptureStderr.clear();
      final process = await startTrackedProcessBounded(
        mitmdump,
        <String>[
          '-p',
          '$port',
          '-s',
          addonPath,
          '-w',
          '$networkDir/flows.mitm',
        ],
        environment: <String, String>{
          'OPENHAND_NETWORK_JSONL': networkJsonlPath,
        },
        timeout: _kNetworkCaptureProcessStartTimeout,
        tag: _kTag,
        startInNewProcessGroup: true,
      );
      startedProcess = process;
      if (!_canContinueNetworkCaptureStart(generation)) {
        await terminateTrackedProcessTree(
          process,
          gracefulTimeout: _kNetworkCaptureStopGrace,
        );
        return _networkCaptureStartCancelledResult();
      }
      _networkCaptureProcess = process;
      _networkCaptureStartedAt = DateTime.now();
      await _wireNetworkCaptureStreams(process);
      if (!_canContinueNetworkCaptureStart(generation)) {
        await _stopNetworkCaptureResources();
        return _networkCaptureStartCancelledResult();
      }
      _safeNotify();
      try {
        final exitCode = await process.exitCode.timeout(
          _kNetworkCaptureStartupProbe,
        );
        final stdoutText = networkCaptureTranscript;
        if (identical(_networkCaptureProcess, process)) {
          _networkCaptureProcess = null;
          _networkCaptureStartedAt = null;
        }
        await _cancelNetworkCaptureSubscriptions();
        _safeNotify();
        return AdbCommandResult(
          args: const <String>['network-capture', 'start'],
          exitCode: exitCode,
          stdout: stdoutText,
          stderr: exitCode == 0
              ? ''
              : 'mitmdump 在启动期间退出，请检查端口占用和 mitmproxy 安装状态。',
          displayCommand:
              'OPENHAND_NETWORK_JSONL=$networkJsonlPath mitmdump -p $port -s $addonPath -w $networkDir/flows.mitm',
        );
      } on TimeoutException {
        if (!_canContinueNetworkCaptureStart(generation)) {
          await _stopNetworkCaptureResources();
          return _networkCaptureStartCancelledResult();
        }
        return AdbCommandResult(
          args: const <String>['network-capture', 'start'],
          exitCode: 0,
          stdout: <String>[
            'mitmdump 捕获已启动',
            '进程 ID：${process.pid}',
            '端口：$port',
            'JSONL：$networkJsonlPath',
            '流量文件：$networkDir/flows.mitm',
          ].join('\n'),
          stderr: '',
          displayCommand:
              'OPENHAND_NETWORK_JSONL=$networkJsonlPath mitmdump -p $port -s $addonPath -w $networkDir/flows.mitm',
        );
      }
    } catch (e, st) {
      silentLog(_kTag, '启动网络捕获失败', e, st);
      final process = startedProcess;
      if (process != null) {
        await runAsyncCleanupBounded(
          () => terminateTrackedProcessTree(
            process,
            gracefulTimeout: _kNetworkCaptureStopGrace,
          ),
          timeout: _kRuntimeCleanupTimeout,
          onError: (error, stack) =>
              silentLog(_kTag, '清理启动失败的网络捕获', error, stack),
        );
      }
      _networkCaptureProcess = null;
      _networkCaptureStartedAt = null;
      await _cancelNetworkCaptureSubscriptions();
      _safeNotify();
      return AdbCommandResult(
        args: const <String>['network-capture', 'start'],
        exitCode: -1,
        stdout: networkCaptureTranscript,
        stderr: '$e',
        displayCommand: _kNetworkCaptureDisplayCommand,
      );
    }
  }

  Future<AdbCommandResult> stopNetworkCapture() async {
    _networkCaptureGeneration += 1;
    final process = _networkCaptureProcess;
    if (process == null) {
      final startPending = _networkCaptureStartFuture != null;
      return AdbCommandResult(
        args: const <String>['network-capture', 'stop'],
        exitCode: 0,
        stdout: networkCaptureTranscript,
        stderr: startPending ? '网络捕获启动取消请求已提交。' : 'mitmdump 未运行。',
        displayCommand: _kNetworkCaptureStopDisplayCommand,
      );
    }
    await _stopNetworkCaptureResources();
    int exitCode = 0;
    try {
      exitCode = await process.exitCode.timeout(_kNetworkCaptureExitWait);
    } catch (_) {
      exitCode = -1;
    }
    _safeNotify();
    return AdbCommandResult(
      args: const <String>['network-capture', 'stop'],
      exitCode: exitCode,
      stdout: networkCaptureTranscript,
      stderr: exitCode == -1 ? 'mitmdump 收到 SIGTERM 后仍未在限时内退出。' : '',
      timedOut: exitCode == -1,
      displayCommand: _kNetworkCaptureStopDisplayCommand,
    );
  }

  Future<AdbCommandResult> readNetworkCaptureSummary({int lines = 120}) async {
    final boundedLines = lines.clamp(20, 600);
    return _runLocalShellDetailed(
      actionName: 'network-capture-read',
      command: _networkCaptureReadScript,
      environment: <String, String>{
        'NETWORK_JSONL': networkJsonlPath,
        'NETWORK_DIR': networkDir,
        'TAIL_LINES': '$boundedLines',
      },
      timeout: _kStaticArtifactReadTimeout,
      displayCommand: '读取网络捕获产物',
      tag: 'android_reverse.network_read',
    );
  }

  Future<AdbCommandResult> exportMitmproxyFlows() async {
    return _runLocalShellDetailed(
      actionName: 'network-capture-export',
      command: _networkCaptureExportScript,
      environment: <String, String>{'NETWORK_DIR': networkDir},
      timeout: _kLocalShellActionTimeout,
      displayCommand: '导出 mitmproxy 流量',
      tag: 'android_reverse.network_export',
    );
  }

  Future<AdbCommandResult> readStaticQuickScanArtifacts({
    String? apkPath,
    String? packageName,
  }) async {
    var quickScanDir = _lastStaticQuickScanDir?.trim();
    if (quickScanDir == null || quickScanDir.isEmpty) {
      final resolved = await _resolveStaticApkForAction(
        'static-read-quick-scan',
        apkPath: apkPath,
        packageName: packageName,
        requireApk: false,
      );
      if (resolved == null) {
        return const AdbCommandResult(
          args: <String>['static-read-quick-scan'],
          exitCode: -1,
          stdout: '',
          stderr: '请先运行快速扫描或配置 APK 路径。',
          displayCommand: _kReadQuickScanDisplayCommand,
        );
      }
      quickScanDir = '$decompiledDir/${resolved.slug}/quick_scan';
    }
    if (!await isDirectoryPath(quickScanDir, followLinks: true)) {
      return AdbCommandResult(
        args: const <String>['static-read-quick-scan'],
        exitCode: -1,
        stdout: '',
        stderr: '快速扫描产物不存在：$quickScanDir',
        displayCommand: _kReadQuickScanDisplayCommand,
      );
    }
    return _runLocalShellDetailed(
      actionName: 'static-read-quick-scan',
      command: _staticQuickScanReadScript,
      environment: <String, String>{'QUICK_SCAN_DIR': quickScanDir},
      timeout: _kStaticArtifactReadTimeout,
      displayCommand: _kReadQuickScanDisplayCommand,
      tag: 'android_reverse.static_read',
    );
  }

  Future<AdbCommandResult> inspectApkIdentity({
    String? apkPath,
    String? packageName,
  }) {
    return _runStaticApkShellAction(
      actionName: 'static-apk-identity',
      apkPath: apkPath,
      packageName: packageName,
      outputCategory: 'identity',
      command: _staticApkIdentityScript,
      timeout: _kStaticIdentityTimeout,
      displayCommand: '检查 APK 身份与签名证书',
      tag: 'android_reverse.static_identity',
    );
  }

  Future<AdbCommandResult> runJadxDecompile({
    String? apkPath,
    String? packageName,
  }) {
    return _runStaticApkShellAction(
      actionName: 'static-jadx',
      apkPath: apkPath,
      packageName: packageName,
      outputCategory: 'jadx_${_artifactTimestamp()}',
      command: _staticJadxScript,
      timeout: _kStaticDecompileTimeout,
      displayCommand: '使用 jadx 反编译 APK',
      tag: 'android_reverse.static_jadx',
    );
  }

  Future<AdbCommandResult> runApktoolUnpack({
    String? apkPath,
    String? packageName,
  }) {
    return _runStaticApkShellAction(
      actionName: 'static-apktool',
      apkPath: apkPath,
      packageName: packageName,
      outputCategory: 'apktool_${_artifactTimestamp()}',
      command: _staticApktoolScript,
      timeout: _kStaticDecompileTimeout,
      displayCommand: '使用 apktool 解包 APK',
      tag: 'android_reverse.static_apktool',
    );
  }

  Future<AdbCommandResult> runStaticStringsScan({
    String? apkPath,
    String? packageName,
  }) {
    return _runStaticApkShellAction(
      actionName: 'static-strings',
      apkPath: apkPath,
      packageName: packageName,
      outputCategory: 'strings_${_artifactTimestamp()}',
      command: _staticStringsScript,
      timeout: _kStaticStringsTimeout,
      displayCommand: '扫描 APK 字符串',
      tag: 'android_reverse.static_strings',
    );
  }

  Future<AdbCommandResult> readCertificateArtifacts({
    String? packageName,
  }) async {
    await ensureCertificateArtifacts(packageName: packageName);
    return _runLocalShellDetailed(
      actionName: 'certs-read-artifacts',
      command: _certificateArtifactsReadScript,
      environment: <String, String>{'CERTS_DIR': certsDir},
      timeout: _kStaticArtifactReadTimeout,
      displayCommand: '读取证书产物',
      tag: 'android_reverse.certs_read',
    );
  }

  Future<AdbCommandResult> inspectMitmproxyCa({String? certPath}) async {
    await ensureCertificateArtifacts();
    return _runLocalShellDetailed(
      actionName: 'certs-inspect-mitm-ca',
      command: _mitmproxyCaInspectScript,
      environment: <String, String>{
        if (certPath?.trim().isNotEmpty ?? false)
          'MITM_CERT_PATH': certPath!.trim(),
      },
      timeout: _kStaticIdentityTimeout,
      displayCommand: '检查 mitmproxy CA',
      tag: 'android_reverse.certs_mitm_ca',
    );
  }

  Future<AdbCommandResult> installMitmproxyCaAsSystemCert({
    String? certPath,
    String? serial,
  }) async {
    await ensureCertificateArtifacts();
    return runLocalArtifactScriptDetailed(
      scriptPath: installMitmCaRootScriptPath,
      args: <String>[
        if (certPath?.trim().isNotEmpty ?? false) certPath!.trim(),
      ],
      environment: <String, String>{
        if (serial?.trim().isNotEmpty ?? false) 'ADB_SERIAL': serial!.trim(),
      },
      timeout: const Duration(seconds: 35),
      displayCommand: '将 mitmproxy CA 安装为系统证书',
      tag: 'android_reverse.certs_install_system_ca',
    );
  }

  // ── 内部 ───────────────────────────────────────────────────────────────

  Future<AdbCommandResult> _runStaticApkShellAction({
    required String actionName,
    required String? apkPath,
    required String? packageName,
    required String outputCategory,
    required String command,
    required Duration timeout,
    required String displayCommand,
    required String tag,
  }) async {
    final resolved = await _resolveStaticApkForAction(
      actionName,
      apkPath: apkPath,
      packageName: packageName,
    );
    if (resolved == null) {
      return AdbCommandResult(
        args: <String>[actionName, '<missing-apk>'],
        exitCode: -1,
        stdout: '',
        stderr: '必须提供指向现有文件的 APK 路径。',
        displayCommand: displayCommand,
      );
    }
    final outputDir = Directory(
      '$decompiledDir/${resolved.slug}/$outputCategory',
    );
    await createDirectoryBounded(outputDir);
    return _runLocalShellDetailed(
      actionName: actionName,
      command: command,
      environment: <String, String>{
        'APK_PATH': resolved.apkPath,
        'OUT_DIR': outputDir.path,
      },
      timeout: timeout,
      displayCommand: displayCommand,
      tag: tag,
    );
  }

  Future<_ResolvedStaticApk?> _resolveStaticApkForAction(
    String actionName, {
    required String? apkPath,
    required String? packageName,
    bool requireApk = true,
  }) async {
    final rawApkPath = (apkPath ?? config.apkPath ?? '').trim();
    if (rawApkPath.isEmpty) {
      if (requireApk) return null;
      final fallbackSlug = _safeArtifactName(
        _firstNonEmpty(<String?>[packageName, config.packageName]),
      );
      return _ResolvedStaticApk(apkPath: '', slug: fallbackSlug);
    }
    if (requireApk && !await isRegularFilePath(rawApkPath, followLinks: true)) {
      return null;
    }
    return _ResolvedStaticApk(
      apkPath: rawApkPath,
      slug: _safeArtifactName(
        _firstNonEmpty(<String?>[
          packageName,
          config.packageName,
          _basenameWithoutExtension(rawApkPath),
          actionName,
        ]),
      ),
    );
  }

  Future<AdbCommandResult> _runLocalShellDetailed({
    required String actionName,
    required String command,
    required Map<String, String> environment,
    required Duration timeout,
    required String? displayCommand,
    required String tag,
  }) async {
    if (Platform.isWindows) {
      return AdbCommandResult(
        args: <String>[actionName],
        exitCode: -1,
        stdout: '',
        stderr: '本地 shell 操作需要 /bin/sh。',
        displayCommand: displayCommand,
      );
    }
    try {
      final startedAt = Stopwatch()..start();
      final result = await runTrackedProcessOrFailed(
        '/bin/sh',
        <String>['-lc', command],
        timeout: timeout,
        tag: tag,
        environment: environment,
      );
      startedAt.stop();
      final stdoutText = result.stdout.toString();
      final stderrText = result.stderr.toString();
      final timedOut =
          result.exitCode == -1 &&
          stdoutText.trim().isEmpty &&
          stderrText.trim().isEmpty &&
          startedAt.elapsed >= timeout;
      return AdbCommandResult(
        args: <String>[actionName],
        exitCode: result.exitCode,
        stdout: stdoutText,
        stderr: timedOut
            ? '本地 shell 操作执行超过 ${timeout.inSeconds} 秒。'
            : stderrText,
        timedOut: timedOut,
        displayCommand: displayCommand ?? actionName,
      );
    } catch (e, st) {
      silentLog(_kTag, '执行本地 Shell', e, st);
      return AdbCommandResult(
        args: <String>[actionName],
        exitCode: -1,
        stdout: '',
        stderr: '$e',
        displayCommand: displayCommand,
      );
    }
  }

  Future<String?> _resolveLocalExecutable(String name) async {
    final executable = nullIfBlank(name);
    if (Platform.isWindows || executable == null) return null;
    final result = await runTrackedProcessOrFailed(
      '/bin/sh',
      <String>['-lc', 'command -v "\$TOOL_NAME" || true'],
      timeout: const Duration(seconds: 3),
      tag: 'android_reverse.resolve_executable',
      environment: <String, String>{'TOOL_NAME': executable},
    );
    if (result.exitCode != 0) return null;
    final path = result.stdout.toString().trim().split('\n').firstOrNull;
    if (path == null || path.isEmpty) return null;
    return path;
  }

  Future<void> _wireNetworkCaptureStreams(Process process) async {
    await _cancelNetworkCaptureSubscriptions();
    if (_disposed || !identical(_networkCaptureProcess, process)) return;
    _networkCaptureStdoutSub = process.stdout
        .transform(utf8.decoder)
        .listen(
          _networkCaptureStdout.add,
          onError: (Object error, StackTrace stack) {
            silentLog(_kTag, 'mitmdump 标准输出流', error, stack);
          },
          cancelOnError: true,
        );
    _networkCaptureStderrSub = process.stderr
        .transform(utf8.decoder)
        .listen(
          _networkCaptureStderr.add,
          onError: (Object error, StackTrace stack) {
            silentLog(_kTag, 'mitmdump 标准错误流', error, stack);
          },
          cancelOnError: true,
        );
    unawaited(
      process.exitCode.then<void>(
        (exitCode) {
          (exitCode == 0 ? _networkCaptureStdout : _networkCaptureStderr).add(
            '\nmitmdump 已退出，退出码：$exitCode\n',
          );
          if (_networkCaptureProcess?.pid == process.pid) {
            _networkCaptureProcess = null;
            _networkCaptureStartedAt = null;
            unawaited(_cancelNetworkCaptureSubscriptions());
            _safeNotify();
          }
        },
        onError: (Object error, StackTrace stack) {
          silentLog(_kTag, '监听 mitmdump 退出状态', error, stack);
        },
      ),
    );
  }

  Future<void> _stopNetworkCaptureResources() async {
    final active = _networkCaptureStopFuture;
    if (active != null) return active;
    late final Future<void> stopping;
    stopping = _stopNetworkCaptureResourcesUncached().whenComplete(() {
      if (identical(_networkCaptureStopFuture, stopping)) {
        _networkCaptureStopFuture = null;
      }
    });
    _networkCaptureStopFuture = stopping;
    return stopping;
  }

  Future<void> _stopNetworkCaptureResourcesUncached() async {
    final process = _networkCaptureProcess;
    _networkCaptureProcess = null;
    _networkCaptureStartedAt = null;
    if (process != null) {
      await runAsyncCleanupBounded(
        () => terminateTrackedProcessTree(
          process,
          gracefulTimeout: _kNetworkCaptureStopGrace,
        ),
        timeout: _kDeviceReportTimeout,
        onError: (error, stack) => silentLog(_kTag, '终止网络捕获', error, stack),
      );
    }
    await _cancelNetworkCaptureSubscriptions();
  }

  Future<void> _cancelNetworkCaptureSubscriptions() async {
    final stdoutSub = _networkCaptureStdoutSub;
    final stderrSub = _networkCaptureStderrSub;
    _networkCaptureStdoutSub = null;
    _networkCaptureStderrSub = null;
    await Future.wait<bool>(<Future<bool>>[
      cancelStreamSubscriptionBounded<String>(
        stdoutSub,
        onError: (error, stack) =>
            silentLog(_kTag, '取消 mitmdump 标准输出订阅', error, stack),
      ),
      cancelStreamSubscriptionBounded<String>(
        stderrSub,
        onError: (error, stack) =>
            silentLog(_kTag, '取消 mitmdump 标准错误订阅', error, stack),
      ),
    ]);
  }

  Future<String> _writeMcpLinkageArtifacts({required bool updateError}) async {
    try {
      await Future.wait(<Future<void>>[
        createDirectoryBounded(Directory(mcpDir)),
        createDirectoryBounded(Directory(fridaScriptsDir)),
        createDirectoryBounded(Directory(fridaOutputDir)),
        createDirectoryBounded(Directory(networkDir)),
        createDirectoryBounded(Directory(scriptsDir)),
        createDirectoryBounded(Directory(toolchainDir)),
      ]);
      final generatedAt = DateTime.now().toUtc().toIso8601String();
      await Future.wait(<Future<void>>[
        writeFileAtomically(
          File(mcpTemplatesPath),
          _mcpLinkageTemplatesJson(generatedAt),
        ),
        writeFileAtomically(File(mcpReadmePath), _mcpLinkageReadme),
        writeFileAtomically(File(mcpSetupGuidePath), _mcpSetupGuideReadme),
        writeFileAtomically(File(fridaReadmePath), _fridaRunbookReadme),
        writeFileAtomically(File(fridaDoctorScriptPath), _fridaDoctorScript),
        writeFileAtomically(File(fridaCaptureScriptPath), _fridaCaptureScript),
        writeFileAtomically(File(networkReadmePath), _networkCaptureReadme),
        writeFileAtomically(
          File(networkProxyProbeScriptPath),
          _networkProxyProbeScript,
        ),
        writeFileAtomically(File(mitmproxyAddonPath), _mitmproxyJsonlAddon),
        writeFileAtomically(File(scriptsReadmePath), _reproduceScriptsReadme),
        writeFileAtomically(
          File(reproducePythonPath),
          _reproduceHttpPythonScript,
        ),
        writeFileAtomically(File(reproduceCurlPath), _reproduceCurlScript),
        writeFileAtomically(
          File(evidenceBundleScriptPath),
          _evidenceBundleScript,
        ),
        writeFileAtomically(File(toolchainReadmePath), _toolchainSetupReadme),
        writeFileAtomically(
          File(toolchainSetupCommandsPath),
          _toolchainSetupCommandsJson(),
        ),
        writeFileAtomically(File(adbOneShotScriptPath), _adbOneShotScript),
        writeFileAtomically(
          File(dynamicProbeScriptPath),
          _androidDynamicProbeScript,
        ),
      ]);
      if (!Platform.isWindows) {
        await runTrackedProcessOrFailed(
          _kAndroidReverseChmodExecutable,
          <String>[
            '+x',
            adbOneShotScriptPath,
            dynamicProbeScriptPath,
            networkProxyProbeScriptPath,
            fridaDoctorScriptPath,
            fridaCaptureScriptPath,
            reproducePythonPath,
            reproduceCurlPath,
            evidenceBundleScriptPath,
          ],
          timeout: _kArtifactChmodTimeout,
          tag: 'android_reverse.mcp_linkage_chmod',
        );
      }
      return <String>[
        'MCP 关联产物：$mcpDir',
        'templates_json: $mcpTemplatesPath',
        'readme: $mcpReadmePath',
        'setup_guide: $mcpSetupGuidePath',
        'adb_one_shot: $adbOneShotScriptPath',
        'dynamic_probe: $dynamicProbeScriptPath',
        'frida_readme: $fridaReadmePath',
        'frida_doctor: $fridaDoctorScriptPath',
        'frida_capture: $fridaCaptureScriptPath',
        'network_readme: $networkReadmePath',
        'network_proxy_probe: $networkProxyProbeScriptPath',
        'scripts_readme: $scriptsReadmePath',
        'reproduce_python: $reproducePythonPath',
        'reproduce_curl: $reproduceCurlPath',
        'evidence_bundle: $evidenceBundleScriptPath',
        'toolchain_readme: $toolchainReadmePath',
        'toolchain_setup_commands: $toolchainSetupCommandsPath',
      ].join('\n');
    } catch (e, st) {
      if (updateError) {
        _errorMessage = '$e';
        _safeNotify();
        rethrow;
      }
      silentLog(_kTag, '写入 MCP 关联产物失败', e, st);
      return '写入 MCP 关联产物失败：$e';
    }
  }

  Future<void> _ensureArtifactDirectories() async {
    try {
      await createDirectoryBounded(Directory(artifactsRootDir));
      await Future.wait<Directory>(
        _kAndroidReverseArtifactSubdirs.map(
          (name) =>
              createDirectoryBounded(Directory('$artifactsRootDir/$name')),
        ),
      );
      await Future.wait(<Future<File>>[
        File(
          logcatJsonlPath,
        ).create(recursive: true).timeout(_kArtifactFileOperationTimeout),
        File(
          networkJsonlPath,
        ).create(recursive: true).timeout(_kArtifactFileOperationTimeout),
      ]);
    } catch (e, st) {
      silentLog(_kTag, '准备产物目录', e, st);
      _errorMessage = '$e';
    }
  }

  Future<void> _refreshDevices() {
    final active = _deviceRefreshFuture;
    if (active != null) {
      _deviceRefreshQueued = true;
      return active;
    }
    late final Future<void> tracked;
    tracked = _drainDeviceRefreshQueue().whenComplete(() {
      if (identical(_deviceRefreshFuture, tracked)) {
        _deviceRefreshFuture = null;
      }
    });
    _deviceRefreshFuture = tracked;
    return tracked;
  }

  Future<void> _drainDeviceRefreshQueue() async {
    do {
      _deviceRefreshQueued = false;
      await _refreshDevicesOnce();
    } while (_deviceRefreshQueued &&
        !_disposed &&
        _state != AndroidReverseSessionState.stopped);
  }

  Future<void> _refreshDevicesOnce() async {
    try {
      final devices = await _adbClient.listDevices();
      if (_disposed || _state == AndroidReverseSessionState.stopped) return;
      _allDevices = List<AdbDevice>.unmodifiable(devices);
      _connectedDevice = _adbClient.selectOnlineDevice(_allDevices);
      if (_state == AndroidReverseSessionState.running &&
          _connectedDevice == null &&
          devices.isNotEmpty) {
        _state = AndroidReverseSessionState.deviceLost;
      } else if (_state == AndroidReverseSessionState.deviceLost &&
          _connectedDevice != null) {
        _state = AndroidReverseSessionState.running;
      }
      _errorMessage = null;
    } catch (e, st) {
      silentLog(_kTag, '刷新设备', e, st);
      if (_disposed || _state == AndroidReverseSessionState.stopped) return;
      _errorMessage = '$e';
    }
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  AdbCommandResult _combineAdbResults(List<AdbCommandResult> results) {
    if (results.isEmpty) {
      return const AdbCommandResult(
        args: <String>['batch'],
        exitCode: 0,
        stdout: '',
        stderr: '',
      );
    }
    final firstFailed = results.where((result) => !result.ok).firstOrNull;
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    for (final result in results) {
      final out = result.stdout.trim();
      final err = result.stderr.trim();
      stdout
        ..writeln('\$ ${result.commandLine}')
        ..writeln('退出码：${result.exitCode}');
      if (out.isNotEmpty) stdout.writeln(out);
      if (err.isNotEmpty) {
        stderr
          ..writeln('\$ ${result.commandLine}')
          ..writeln(err);
      }
      stdout.writeln();
    }
    return AdbCommandResult(
      args: const <String>['batch'],
      exitCode: firstFailed?.exitCode ?? 0,
      stdout: stdout.toString().trimRight(),
      stderr: stderr.toString().trimRight(),
      timedOut: results.any((result) => result.timedOut),
    );
  }

  Future<void> _warmStaticQuickScanFromConfig() async {
    final apkPath = config.apkPath?.trim();
    if (apkPath == null || apkPath.isEmpty) return;
    try {
      final result = await runStaticQuickScan(
        apkPath: apkPath,
        packageName: config.packageName,
        timeout: _kStaticQuickScanWarmTimeout,
      );
      if (!result.ok && !result.hasUsableStdout) {
        silentLog(_kTag, '预热静态快速扫描失败', result.combinedOutput);
      }
    } catch (e, st) {
      silentLog(_kTag, '预热静态快速扫描异常', e, st);
    }
  }

  String _artifactTimestamp() {
    return DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
  }

  String _safeArtifactName(String value) {
    final cleaned = collapseRepeatedUnderscores(
      value.trim().replaceAll(RegExp('[^A-Za-z0-9_.-]+'), '_'),
    ).replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'artifact' : cleaned;
  }

  String _basenameWithoutExtension(String path) {
    final name = path.split('/').last.trim();
    if (name.toLowerCase().endsWith('.apk')) {
      return name.substring(0, name.length - 4);
    }
    return name.isEmpty ? 'apk' : name;
  }

  String _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty && trimmed != '<pkg>') {
        return trimmed;
      }
    }
    return 'artifact';
  }

  String _packageDumpsysSummary(String raw) {
    final summary = <String>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final isSectionHeader =
          trimmed == 'requested permissions:' ||
          trimmed == 'install permissions:' ||
          trimmed == 'runtime permissions:' ||
          trimmed == 'PackageSignatures{' ||
          trimmed.startsWith('SigningDetails') ||
          trimmed.startsWith('Activities:') ||
          trimmed.startsWith('Services:') ||
          trimmed.startsWith('Receivers:') ||
          trimmed.startsWith('Providers:');
      final isKeyLine =
          trimmed.startsWith('versionCode=') ||
          trimmed.startsWith('versionName=') ||
          trimmed.startsWith('targetSdk=') ||
          trimmed.startsWith('minSdk=') ||
          trimmed.startsWith('firstInstallTime=') ||
          trimmed.startsWith('lastUpdateTime=') ||
          trimmed.startsWith('installerPackageName=') ||
          trimmed.startsWith('signatures=') ||
          trimmed.startsWith('pkgFlags=') ||
          trimmed.startsWith('privateFlags=') ||
          trimmed.startsWith('User 0:') ||
          trimmed.startsWith('enabled=') ||
          trimmed.startsWith('stopped=') ||
          trimmed.startsWith('hidden=') ||
          trimmed.startsWith('suspended=');
      final isComponentLine =
          trimmed.contains('Activity') ||
          trimmed.contains('Service') ||
          trimmed.contains('Receiver') ||
          trimmed.contains('Provider');
      final isPermissionLine = trimmed.startsWith('android.permission.');
      if (isSectionHeader || isKeyLine || isPermissionLine || isComponentLine) {
        summary.add(trimmed);
      }
      if (summary.length >= _kPackageReportSummaryMaxLines) break;
    }
    if (summary.isEmpty && raw.trim().isNotEmpty) {
      return trimRightNonEmptyLines(
        raw.split('\n'),
        limit: _kPackageReportSummaryMaxLines,
      ).join('\n');
    }
    return summary.join('\n');
  }

  Future<String> _staticQuickScanSummary(
    Directory outputDir,
    ProcessResult result, {
    required bool timedOut,
  }) async {
    final buffer = StringBuffer()
      ..writeln('静态快速扫描输出：${outputDir.path}')
      ..writeln('退出码：${result.exitCode}');
    final deadline = MonotonicDeadline(
      _kStaticArtifactReadTimeout,
      timeoutMessage: '静态快速扫描摘要读取超时。',
    );
    if (timedOut) {
      buffer.writeln('状态：执行超时，部分产物仍可使用');
    }
    final files = <String>[
      'SUMMARY.md',
      'badging.txt',
      'manifest.txt',
      'components.txt',
      'certs.txt',
      'zip_listing.txt',
      'nested_apks.txt',
      'flutter.txt',
      'native_libs.txt',
      'suspicious_files.txt',
      'network_candidates.txt',
      'business_urls.txt',
      'business_domains.txt',
      'business_network_sources.txt',
      'urls.txt',
      'domains.txt',
      'ips.txt',
      'network_sources.txt',
      'interesting_strings.txt',
    ];
    try {
      for (final name in files) {
        final file = File('${outputDir.path}/$name');
        if (!await file.exists().timeout(
          deadline.limit(defaultBoundedFileReadIdleTimeout),
        )) {
          continue;
        }
        buffer
          ..writeln()
          ..writeln('## $name');
        try {
          final preview = await readBoundedUtf8Lines(
            file,
            startLine: 1,
            maxLines: _kStaticQuickScanPreviewLines,
            maxScanBytes: _kStaticQuickScanPreviewMaxBytes,
            maxLineCharacters: _kStaticQuickScanPreviewLineMaxCharacters,
            idleTimeout: deadline.limit(defaultBoundedFileReadIdleTimeout),
            totalTimeout: deadline.remaining(),
          );
          if (preview.lines.isEmpty) {
            buffer.writeln('(empty)');
          } else {
            buffer
              ..write(preview.lines.join('\n'))
              ..writeln();
          }
        } on FileSystemException catch (error, stack) {
          silentLog(_kTag, '读取静态快速扫描摘要文件失败', error, stack);
          buffer.writeln('(unavailable)');
        } on BoundedFileReadException catch (error, stack) {
          silentLog(_kTag, '读取静态快速扫描摘要文件失败', error, stack);
          buffer.writeln('(unavailable)');
        }
      }
    } on TimeoutException catch (error, stack) {
      silentLog(_kTag, '读取静态快速扫描摘要超时', error, stack);
      buffer
        ..writeln()
        ..writeln('(remaining previews unavailable)');
    } finally {
      deadline.stop();
    }
    final stderr = result.stderr.toString().trim();
    if (stderr.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## stderr')
        ..writeln(stderr);
    }
    return buffer.toString().trimRight();
  }

  String _deviceReportMarkdown({
    required String capturedAt,
    required String serial,
    required List<AdbDevice> devices,
    required Map<String, String> props,
    required String? forwards,
    required String? reverses,
    required String? packageName,
    required String? launcher,
    required AdbCommandResult snapshot,
    required AdbCommandResult logcat,
    required String jsonPath,
  }) {
    final buffer = StringBuffer()
      ..writeln('# Android device field report')
      ..writeln()
      ..writeln('- captured_at: $capturedAt')
      ..writeln('- serial: $serial')
      ..writeln('- json: $jsonPath');
    final keyProps = <String>[
      'ro.product.manufacturer',
      'ro.product.brand',
      'ro.product.model',
      'ro.product.device',
      'ro.build.version.release',
      'ro.build.version.sdk',
      'ro.product.cpu.abi',
      'ro.product.cpu.abilist',
      'ro.build.fingerprint',
    ];
    buffer
      ..writeln()
      ..writeln('## Devices');
    if (devices.isEmpty) {
      buffer.writeln('(none)');
    } else {
      for (final device in devices) {
        buffer.writeln(
          '- ${device.serial} ${device.state}'
          '${device.model == null ? "" : " model=${device.model}"}'
          '${device.product == null ? "" : " product=${device.product}"}',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('## Key properties');
    for (final key in keyProps) {
      buffer.writeln('- $key: ${props[key] ?? "-"}');
    }
    buffer
      ..writeln()
      ..writeln('## Target package')
      ..writeln(
        '- package: ${packageName?.isEmpty == false ? packageName : "-"}',
      )
      ..writeln('- launcher: ${launcher?.isEmpty == false ? launcher : "-"}')
      ..writeln()
      ..writeln('## Forwards')
      ..writeln(_fenced(forwards?.trim()))
      ..writeln()
      ..writeln('## Reverses')
      ..writeln(_fenced(reverses?.trim()))
      ..writeln()
      ..writeln('## Snapshot')
      ..writeln(_fenced(snapshot.stdout.trim()))
      ..writeln()
      ..writeln('## Logcat tail')
      ..writeln(_fenced(logcat.stdout.trim()));
    final stderr = <String>[
      if (snapshot.stderr.trim().isNotEmpty) snapshot.stderr.trim(),
      if (logcat.stderr.trim().isNotEmpty) logcat.stderr.trim(),
    ].join('\n');
    if (stderr.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Warnings')
        ..writeln(_fenced(stderr.trim()));
    }
    return buffer.toString().trimRight();
  }

  String _packageReportMarkdown({
    required String capturedAt,
    required String packageName,
    required List<String> paths,
    required String? version,
    required String? launcher,
    required AdbCommandResult dumpsys,
    required String summary,
    required String jsonPath,
  }) {
    final buffer = StringBuffer()
      ..writeln('# Android package report')
      ..writeln()
      ..writeln('- captured_at: $capturedAt')
      ..writeln('- package: $packageName')
      ..writeln('- version: ${version?.isEmpty == false ? version : "-"}')
      ..writeln('- launcher: ${launcher?.isEmpty == false ? launcher : "-"}')
      ..writeln('- json: $jsonPath')
      ..writeln()
      ..writeln('## APK paths');
    if (paths.isEmpty) {
      buffer.writeln('(none)');
    } else {
      for (final path in paths) {
        buffer.writeln('- $path');
      }
    }
    buffer
      ..writeln()
      ..writeln('## dumpsys summary')
      ..writeln(_fenced(summary));
    if (dumpsys.timedOut || dumpsys.stderr.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Warnings')
        ..writeln(
          _fenced(
            <String>[
              if (dumpsys.timedOut) 'dumpsys package timed out',
              if (dumpsys.stderr.trim().isNotEmpty) dumpsys.stderr.trim(),
            ].join('\n'),
          ),
        );
    }
    return buffer.toString().trimRight();
  }

  String _fenced(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return '```text\n(empty)\n```';
    return '```text\n$text\n```';
  }

  String _toolchainSetupCommandsJson() {
    final payload = <String, Object?>{
      'source': 'OpenHand Android Reverse dashboard',
      'purpose':
          'dashboard-managed setup actions and Bash fallback metadata for Android reverse tooling',
      'rules': const <String>[
        'Prefer dashboard Toolchain / Plugins actions for install, update, and uninstall.',
        'Fallback commands require user approval before execution.',
        'Prefer reading current toolchain diagnostics before changing tools.',
        'Use Frida doctor before installing, pushing, or starting frida-server.',
      ],
      'tools': androidReverseToolchainProbes
          .map((probe) {
            final pluginId = androidReverseToolchainPluginIdForProbe(probe.id);
            return <String, Object?>{
              'id': probe.id,
              'label': probe.label,
              'required': probe.required,
              if (pluginId != null) ...<String, Object?>{
                'plugin_service_id': pluginId,
                'preferred_action_surface': 'dashboard_plugin_service',
              },
              'install_hint_zh': probe.installHintZh,
              'install_hint_en': probe.installHintEn,
              if (probe.installCommand?.trim().isNotEmpty ?? false)
                'install_command': probe.installCommand!.trim(),
              if (probe.updateCommand?.trim().isNotEmpty ?? false)
                'update_command': probe.updateCommand!.trim(),
              if (probe.uninstallCommand?.trim().isNotEmpty ?? false)
                'uninstall_command': probe.uninstallCommand!.trim(),
              if (probe.referenceUrl?.trim().isNotEmpty ?? false)
                'reference_url': probe.referenceUrl!.trim(),
            };
          })
          .toList(growable: false),
    };
    return prettyPrintJson(payload);
  }

  String _mcpLinkageTemplatesJson(String generatedAt) {
    final serial = config.deviceSerial?.trim();
    final packageName = config.packageName?.trim();
    final payload = <String, Object?>{
      'generated_at': generatedAt,
      'source': 'OpenHand Android Reverse dashboard',
      'config': config.toJson(),
      'artifact_paths': <String, Object?>{
        'mcp_dir': mcpDir,
        'templates_json': mcpTemplatesPath,
        'readme': mcpReadmePath,
        'setup_guide': mcpSetupGuidePath,
        'adb_one_shot': adbOneShotScriptPath,
        'dynamic_probe': dynamicProbeScriptPath,
        'frida_readme': fridaReadmePath,
        'quick_scan_root': decompiledDir,
        'logcat_jsonl': logcatJsonlPath,
        'network_jsonl': networkJsonlPath,
        'network_readme': networkReadmePath,
        'network_proxy_probe': networkProxyProbeScriptPath,
        'mitmproxy_addon': mitmproxyAddonPath,
        'frida_scripts_dir': fridaScriptsDir,
        'frida_output_dir': fridaOutputDir,
        'frida_doctor_script': fridaDoctorScriptPath,
        'frida_capture_script': fridaCaptureScriptPath,
        'scripts_readme': scriptsReadmePath,
        'reproduce_python': reproducePythonPath,
        'reproduce_curl': reproduceCurlPath,
        'evidence_bundle_script': evidenceBundleScriptPath,
        'toolchain_readme': toolchainReadmePath,
        'toolchain_setup_commands': toolchainSetupCommandsPath,
      },
      'tool_search_queries': const <String>[
        'select:adb,android,frida,ida,apktool,jadx,anything-analyzer,flutter',
        'select:logcat,device,shell,package,activity,frida',
      ],
      'rules': const <String>[
        'Use only real mcp__* names from Tool Catalog or ToolSearch results.',
        'If an enabled ADB/Frida MCP is missing, report the missing server and fall back to Bash only after device/tool confirmation.',
        'For flaky wireless ADB, use scripts/adb_one_shot.sh with a short timeout and accept usable stdout from timed-out commands.',
        'Before installing or pushing Frida, run frida/frida_doctor.sh once and branch from its output.',
        'Do not run adb kill-server, adb start-server, or pkill adb without explicit user approval; prefer single-device short-timeout probes.',
        'Do not guess .MainActivity; resolve launcher activity or use dashboard package launch.',
        'Stop after two repeated failures of the same command, install step, hook, or launch path.',
      ],
      'server_templates': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'android-adb-stdio',
          'purpose':
              'ADB shell, package, file transfer, logcat, forward/reverse',
          'config': <String, Object?>{
            'mcpServers': <String, Object?>{
              'android-adb': <String, Object?>{
                'enabled': true,
                'probeEnabled': true,
                'type': 'stdio',
                'transport': 'stdio',
                'visibleTemplateIds': _kAndroidReverseMcpVisibleTemplateIds,
                'command': 'npx',
                'args': const <String>[
                  '-y',
                  '@landicefu/android-adb-mcp-server',
                ],
              },
            },
          },
        },
        <String, Object?>{
          'id': 'frida-stdio',
          'purpose': 'Frida spawn, attach, script load, output read',
          'config': <String, Object?>{
            'mcpServers': <String, Object?>{
              'android-frida': <String, Object?>{
                'enabled': true,
                'probeEnabled': true,
                'type': 'stdio',
                'transport': 'stdio',
                'visibleTemplateIds': _kAndroidReverseMcpVisibleTemplateIds,
                'command': 'npx',
                'args': const <String>['-y', 'frida-mcp'],
              },
            },
          },
        },
        <String, Object?>{
          'id': 'ida-pro-sse',
          'purpose': 'IDA Pro decompiler and database inspection',
          'config': <String, Object?>{
            'mcpServers': <String, Object?>{
              'ida-pro': <String, Object?>{
                'enabled': true,
                'probeEnabled': true,
                'type': 'sse',
                'transport': 'sse',
                'visibleTemplateIds': _kAndroidReverseMcpVisibleTemplateIds,
                'url': 'http://127.0.0.1:<port>/sse',
              },
            },
          },
        },
        <String, Object?>{
          'id': 'anything-analyzer-stdio',
          'purpose': 'APK, ELF, dex, text, archive triage',
          'config': <String, Object?>{
            'mcpServers': <String, Object?>{
              'anything-analyzer': <String, Object?>{
                'enabled': true,
                'probeEnabled': true,
                'type': 'stdio',
                'transport': 'stdio',
                'visibleTemplateIds': _kAndroidReverseMcpVisibleTemplateIds,
                'command': 'npx',
                'args': const <String>['-y', '<anything-analyzer-package>'],
              },
            },
          },
        },
      ],
      'adb_one_shot_examples': <String>[
        '$adbOneShotScriptPath devices',
        '$adbOneShotScriptPath reverse --list',
        if (serial != null && serial.isNotEmpty)
          '$adbOneShotScriptPath -s $serial --timeout 6 getprop ro.product.cpu.abi',
        if (packageName != null && packageName.isNotEmpty)
          '$adbOneShotScriptPath${serial != null && serial.isNotEmpty ? " -s $serial" : ""} --timeout 8 cmd package resolve-activity --brief $packageName',
        if (packageName != null && packageName.isNotEmpty)
          '$adbOneShotScriptPath${serial != null && serial.isNotEmpty ? " -s $serial" : ""} --timeout 8 pidof $packageName',
        '$dynamicProbeScriptPath${serial != null && serial.isNotEmpty ? " -s $serial" : ""}${packageName != null && packageName.isNotEmpty ? " -p $packageName" : ""} --timeout 6',
      ],
      'workflow_checklist': const <String>[
        'Read android_reverse_config and android_reverse_runtime.',
        'If latest_static_quick_scan exists, read its SUMMARY.md before new Bash scanning.',
        'If quick_scan closes on one business URL/domain, deliver the conclusion and evidence paths before dynamic validation.',
        'Read mcp/SETUP.md before relying on MCP tools.',
        'Confirm device with adb devices or ADB MCP.',
        'Run scripts/android_dynamic_probe.sh once before dynamic validation on a flaky device.',
        'Read quick_scan artifacts before dynamic work when APK path exists.',
        'Read network/README.md and run network/proxy_probe.sh before mitmproxy capture.',
        'Use frida/run_frida_capture.sh to preserve Frida stdout/stderr under frida/output/.',
        'Place final curl/Python reproduction in scripts/ and keep scripts/README.md updated.',
        'Use MCP for ADB/Frida only when exact mcp__* tools are visible.',
        'Use dashboard-generated cert/network/frida artifacts instead of rewriting boilerplate.',
      ],
    };
    return prettyPrintJson(payload);
  }
}

const String _mcpLinkageReadme = '''# Android reverse MCP linkage

This directory is generated by the OpenHand Android Reverse dashboard.

Use it as the thread-local source of truth for MCP setup, ToolSearch queries,
and Bash fallback discipline.

Files:
- openhand_android_reverse_mcp_templates.json: MCP templates, checklist, and examples.
- SETUP.md: global MCP setup checklist and fallback decision tree.
- ../scripts/adb_one_shot.sh: short-timeout ADB wrapper for flaky wireless devices.
- ../scripts/android_dynamic_probe.sh: one-pass ADB / launcher / Frida preflight.
- ../network/README.md and ../network/proxy_probe.sh: mitmproxy and proxy diagnostics.
- ../frida/README.md, frida_doctor.sh, run_frida_capture.sh: Frida diagnostics and output capture runbook.
- ../scripts/README.md, reproduce_http.py, reproduce_curl.sh, make_evidence_bundle.sh: final delivery templates.
- ../toolchain/README.md and setup_commands.json: dashboard setup action metadata and Bash fallback commands.

Rules:
1. Use only real mcp__* tool names from the Tool Catalog or ToolSearch result.
2. If ADB/Frida MCP is enabled but absent, report the missing server before Bash fallback.
3. Read quick_scan/SUMMARY.md first. If it closes on one business URL/domain, deliver the static conclusion and evidence paths before Frida or mitmproxy.
4. Do not guess launcher activities. Resolve them with package manager data.
5. Before mitmproxy capture, read network/README.md and run network/proxy_probe.sh.
6. Before any Frida install/push/start action, run frida/frida_doctor.sh once and follow its report.
7. Capture Frida output through frida/run_frida_capture.sh so evidence is preserved under frida/output/.
8. Put final reproductions under scripts/ and run make_evidence_bundle.sh before final delivery.
9. Do not restart the global ADB server (`adb kill-server`, `adb start-server`, `pkill adb`) without explicit user approval.
10. Stop after two repeated failures on the same command, hook, install, or launch path.
''';

const String _mcpSetupGuideReadme = '''# Android reverse MCP setup

Use this checklist before relying on Android reverse MCP tools.

## Read first

1. Prefer the dashboard MCP capability cards to install, update, or uninstall supported servers.
2. Use `openhand_android_reverse_mcp_templates.json` only as fallback metadata.
3. For local HTTP/SSE servers, fill the concrete URL before saving.
4. Refresh the MCP panel and confirm each server is enabled and healthy.
5. Use only exact `mcp__*` tool names shown in the Tool Catalog or ToolSearch result.

## Recommended servers

- ADB: device list, shell, file transfer, package, logcat, forward/reverse.
- Frida: spawn, attach, load script, read output.
- IDA Pro: decompiler and database inspection when an IDA bridge is already running.
- anything-analyzer: archive, APK, dex, ELF, and text triage.

## Fallback

- If a requested MCP is enabled in config but missing from the Tool Catalog, report it first.
- If `latest_static_quick_scan` exists in runtime metadata, read its `SUMMARY.md` before new Bash scanning.
- If quick_scan already identifies one business URL/domain, deliver the static conclusion first; ask before dynamic validation.
- Use Bash fallback only after confirming `adb devices`, local CLI availability, and the target serial.
- For flaky wireless ADB, prefer `../scripts/adb_one_shot.sh --timeout 6`.
- Before Frida install, push, or start, run `../frida/frida_doctor.sh`.
- Before mitmproxy capture, read `../network/README.md` and run `../network/proxy_probe.sh`.

## Stop rules

- Do not invent MCP tool names.
- Do not repeat the same install, attach, launch, or shell command more than twice.
- Do not run `adb kill-server`, `adb start-server`, or `pkill adb` without user approval.
''';

const String _toolchainSetupReadme = '''# Android reverse toolchain setup

This directory stores dashboard setup action metadata and Bash fallback commands
for Android reverse tooling.

Files:
- setup_commands.json: install, update, uninstall, hint, and reference metadata.

Rules:
1. Prefer the dashboard Toolchain / Plugins buttons for install, update, and uninstall.
2. Read current dashboard diagnostics before changing tools.
3. Ask the user before running any fallback command from setup_commands.json.
4. Do not repeat the same install command after two failures.
5. For Frida, run `../frida/frida_doctor.sh` before installing, pushing, or starting frida-server.
6. Prefer generated quick_scan evidence before installing optional dynamic tools; ask before dynamic validation when static evidence already closes the target.
''';

const String _fridaRunbookReadme = '''# Android reverse Frida runbook

Use this directory for Frida scripts, metadata, and captured output.

Directories:
- scripts/: saved hook scripts and metadata generated by the dashboard.
- output/: stdout/stderr captured from frida, frida-ps, and frida-server checks.
Files:
- frida_doctor.sh: read-only local/device Frida diagnostic; no install, push, or start side effects.
- run_frida_capture.sh: spawn / attach wrapper that tees output to output/.

Preflight:
1. Run ../scripts/android_dynamic_probe.sh before dynamic validation.
2. Run frida_doctor.sh before installing, pushing, or starting Frida.
3. Match frida-server to the local `frida --version` and device ABI.
4. Use launcher data from package reports or dynamic_probe; do not guess `.MainActivity`.
5. If Frida CLI or frida-server is missing, report the gap and ask before installing.
6. Run hooks through run_frida_capture.sh to keep stdout/stderr evidence.

Stop rules:
- Do not repeat the same install, launch, attach, or shell command more than twice.
- If ADB times out but stdout has the needed value, treat it as partial success.
- If static quick_scan already proves one business domain or URL, deliver the conclusion first; Frida is optional validation.
''';

const String _boundedShellTimeoutFunction = r'''
run_with_timeout() {
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$TIMEOUT_SECONDS" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_SECONDS" "$@"
  else
    perl -e '
my $timeout = shift @ARGV;
my $pid = fork();
die "fork failed\n" unless defined $pid;
if ($pid == 0) { exec @ARGV or exit 127; }
$SIG{ALRM} = sub {
  kill "TERM", $pid;
  select undef, undef, undef, 0.2;
  kill "KILL", $pid;
  exit 124;
};
alarm $timeout;
waitpid($pid, 0);
my $status = $?;
alarm 0;
exit($status & 127 ? 128 + ($status & 127) : (($status >> 8) & 255));
' "$TIMEOUT_SECONDS" "$@"
  fi
}
''';

const String _androidAdbProbeArguments = r'''ADB_BIN="${ADB_BIN:-adb}"
TIMEOUT_SECONDS="${ADB_TIMEOUT_SECONDS:-6}"
SERIAL="${ADB_SERIAL:-}"
PACKAGE_NAME="${ANDROID_PACKAGE_NAME:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--serial)
      if [[ $# -lt 2 ]]; then
        echo "missing serial value" >&2
        exit 64
      fi
      SERIAL="${2:-}"
      shift 2
      ;;
    -p|--package)
      if [[ $# -lt 2 ]]; then
        echo "missing package value" >&2
        exit 64
      fi
      PACKAGE_NAME="${2:-}"
      shift 2
      ;;
    --timeout)
      if [[ $# -lt 2 ]]; then
        echo "missing timeout value" >&2
        exit 64
      fi
      TIMEOUT_SECONDS="${2:-6}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 64
      ;;
  esac
done
''';

const String _androidAdbQuickShellFunctions = r'''
adb_quick() {
  local serial_args=()
  if [[ -n "$SERIAL" ]]; then
    serial_args=(-s "$SERIAL")
  fi
  if [[ -x "$ADB_ONE_SHOT" ]]; then
    "$ADB_ONE_SHOT" "${serial_args[@]}" --timeout "$TIMEOUT_SECONDS" "$@"
  else
    run_with_timeout "$ADB_BIN" "${serial_args[@]}" "$@"
  fi
}

section() {
  printf '\n[%s]\n' "$1"
}
''';

const String _fridaDoctorScript =
    r'''#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADB_ONE_SHOT="${ADB_ONE_SHOT:-$SESSION_DIR/scripts/adb_one_shot.sh}"
''' +
    _androidAdbProbeArguments +
    _boundedShellTimeoutFunction +
    _androidAdbQuickShellFunctions +
    r'''
run_section() {
  section "$1"
  shift
  "$@" 2>&1
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    printf '(exit=%s)\n' "$status"
  fi
}

valid_package() {
  [[ "$PACKAGE_NAME" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]]
}

abi_to_frida_suffix() {
  case "$1" in
    arm64-v8a) printf 'android-arm64' ;;
    armeabi-v7a|armeabi) printf 'android-arm' ;;
    x86_64) printf 'android-x86_64' ;;
    x86) printf 'android-x86' ;;
    *) printf 'unknown' ;;
  esac
}

section metadata
printf 'serial=%s\n' "${SERIAL:-auto}"
printf 'package=%s\n' "${PACKAGE_NAME:-unset}"
printf 'timeout_seconds=%s\n' "$TIMEOUT_SECONDS"
printf 'mode=read_only_doctor\n'

section local_frida
if command -v frida >/dev/null 2>&1; then
  LOCAL_FRIDA_VERSION="$(frida --version 2>&1 | head -1)"
  printf 'frida=%s\n' "$LOCAL_FRIDA_VERSION"
else
  LOCAL_FRIDA_VERSION=""
  echo 'frida=missing'
fi
if command -v frida-ps >/dev/null 2>&1; then
  printf 'frida_ps=%s\n' "$(command -v frida-ps)"
else
  echo 'frida_ps=missing'
fi
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY' 2>/dev/null || true
try:
    import frida
    print("python_frida=" + getattr(frida, "__version__", "present"))
except Exception as exc:
    print("python_frida=missing:" + exc.__class__.__name__)
PY
fi

run_section adb_devices "$ADB_BIN" devices -l

section device_abi
DEVICE_ABI="$(adb_quick shell getprop ro.product.cpu.abi 2>&1 | tr -d '\r' | tail -1)"
printf '%s\n' "$DEVICE_ABI"
FRIDA_SUFFIX="$(abi_to_frida_suffix "$DEVICE_ABI")"
printf 'frida_server_suffix=%s\n' "$FRIDA_SUFFIX"

if [[ -n "$LOCAL_FRIDA_VERSION" && "$FRIDA_SUFFIX" != "unknown" ]]; then
  section matching_server_url
  printf 'https://github.com/frida/frida/releases/download/%s/frida-server-%s-%s.xz\n' \
    "$LOCAL_FRIDA_VERSION" "$LOCAL_FRIDA_VERSION" "$FRIDA_SUFFIX"
fi

section device_frida_server
adb_quick shell "pidof frida-server || ps -A | grep frida || ls -l /data/local/tmp/frida* 2>/dev/null || true" 2>&1

section adb_forwards
adb_quick forward --list 2>&1

section adb_reverses
adb_quick reverse --list 2>&1

section frida_ps_probe
if command -v frida-ps >/dev/null 2>&1; then
  run_with_timeout frida-ps -Uai 2>&1 | head -120
  status=$?
  if [[ "$status" -ne 0 ]]; then
    printf '(exit=%s)\n' "$status"
  fi
else
  echo 'frida-ps missing; install frida-tools only after user approval'
fi

if valid_package; then
  section target_process
  adb_quick shell "pidof $PACKAGE_NAME || true" 2>&1
fi

section next_steps
if [[ -z "$LOCAL_FRIDA_VERSION" ]]; then
  echo '- Local Frida CLI is missing. Ask before installing frida-tools.'
elif [[ "$FRIDA_SUFFIX" == "unknown" ]]; then
  echo '- Device ABI is unknown. Resolve ABI before downloading frida-server.'
else
  echo '- If frida-server is missing, download the matching URL above, push it, chmod 755, start it, then re-run this doctor.'
fi
echo '- Do not repeat pip install, push, start, or attach commands after two failures.'
echo '- Use run_frida_capture.sh for spawn/attach so stdout/stderr are saved.'
''';

const String _fridaCaptureScript = r'''#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${FRIDA_OUTPUT_DIR:-$SCRIPT_DIR/output}"
MODE="spawn"
SERIAL="${ADB_SERIAL:-}"
PACKAGE_NAME="${ANDROID_PACKAGE_NAME:-}"
SCRIPT_PATH=""
OUTPUT_NAME=""
EXTRA_ARGS=()

usage() {
  cat >&2 <<'EOF'
usage: run_frida_capture.sh --package PACKAGE --script SCRIPT [--spawn|--attach] [-s SERIAL] [--output-name NAME] [-- FRIDA_ARGS...]

Examples:
  ./run_frida_capture.sh --package com.example.app --script scripts/hook.js --spawn
  ./run_frida_capture.sh --package com.example.app --script scripts/hook.js --attach -- -q
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spawn)
      MODE="spawn"
      shift
      ;;
    --attach)
      MODE="attach"
      shift
      ;;
    -s|--serial)
      if [[ $# -lt 2 ]]; then
        echo "missing serial value" >&2
        exit 64
      fi
      SERIAL="${2:-}"
      shift 2
      ;;
    -p|--package)
      if [[ $# -lt 2 ]]; then
        echo "missing package value" >&2
        exit 64
      fi
      PACKAGE_NAME="${2:-}"
      shift 2
      ;;
    -l|--script)
      if [[ $# -lt 2 ]]; then
        echo "missing script value" >&2
        exit 64
      fi
      SCRIPT_PATH="${2:-}"
      shift 2
      ;;
    --output-name)
      if [[ $# -lt 2 ]]; then
        echo "missing output name" >&2
        exit 64
      fi
      OUTPUT_NAME="${2:-}"
      shift 2
      ;;
    --)
      shift
      EXTRA_ARGS=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ -z "$PACKAGE_NAME" || -z "$SCRIPT_PATH" ]]; then
  usage
  exit 64
fi
if [[ ! "$PACKAGE_NAME" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]]; then
  echo "invalid package name: $PACKAGE_NAME" >&2
  exit 64
fi
if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "script not found: $SCRIPT_PATH" >&2
  exit 66
fi
if ! command -v frida >/dev/null 2>&1; then
  echo "frida not found" >&2
  exit 69
fi

mkdir -p "$OUTPUT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SAFE_PACKAGE="$(printf '%s' "$PACKAGE_NAME" | tr -cd 'A-Za-z0-9_.-')"
SAFE_NAME="$(printf '%s' "${OUTPUT_NAME:-$SAFE_PACKAGE-$MODE}" | tr '/ ' '__' | tr -cd 'A-Za-z0-9_.-')"
BASE="$OUTPUT_DIR/${SAFE_NAME:-frida}_$STAMP"
STDOUT_PATH="$BASE.stdout.log"
STDERR_PATH="$BASE.stderr.log"
META_PATH="$BASE.json"

frida_args=()
if [[ -n "$SERIAL" ]]; then
  frida_args+=("-D" "$SERIAL")
else
  frida_args+=("-U")
fi
if [[ "$MODE" == "spawn" ]]; then
  frida_args+=("-f" "$PACKAGE_NAME" "-l" "$SCRIPT_PATH" "--no-pause")
else
  frida_args+=("-n" "$PACKAGE_NAME" "-l" "$SCRIPT_PATH")
fi
frida_args+=("${EXTRA_ARGS[@]}")

cat > "$META_PATH" <<EOF
{
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "mode": "$MODE",
  "package_name": "$PACKAGE_NAME",
  "script_path": "$SCRIPT_PATH",
  "stdout_path": "$STDOUT_PATH",
  "stderr_path": "$STDERR_PATH"
}
EOF

echo "Frida stdout: $STDOUT_PATH"
echo "Frida stderr: $STDERR_PATH"
echo "Frida metadata: $META_PATH"
frida "${frida_args[@]}" > >(tee "$STDOUT_PATH") 2> >(tee "$STDERR_PATH" >&2)
''';

const String _adbOneShotScript =
    r'''#!/usr/bin/env bash
set -uo pipefail

ADB_BIN="${ADB_BIN:-adb}"
TIMEOUT_SECONDS="${ADB_TIMEOUT_SECONDS:-8}"
SERIAL="${ADB_SERIAL:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--serial)
      if [[ $# -lt 2 ]]; then
        echo "missing serial value" >&2
        exit 64
      fi
      SERIAL="${2:-}"
      shift 2
      ;;
    --timeout)
      if [[ $# -lt 2 ]]; then
        echo "missing timeout value" >&2
        exit 64
      fi
      TIMEOUT_SECONDS="${2:-8}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -eq 0 ]]; then
  echo "usage: adb_one_shot.sh [-s SERIAL] [--timeout SECONDS] <adb-subcommand|shell-command>" >&2
  exit 64
fi
''' +
    _boundedShellTimeoutFunction +
    r'''
run_adb() {
  if [[ -n "$SERIAL" ]]; then
    run_with_timeout "$ADB_BIN" -s "$SERIAL" "$@"
  else
    run_with_timeout "$ADB_BIN" "$@"
  fi
}

case "$1" in
  devices|connect|disconnect)
    run_with_timeout "$ADB_BIN" "$@"
    status=$?
    ;;
  get-state|get-serialno|get-devpath|wait-for-device|root|unroot|remount|reboot|tcpip|usb|jdwp|forward|reverse|install|uninstall|push|pull|logcat)
    run_adb "$@"
    status=$?
    ;;
  shell)
    shift
    if [[ $# -eq 0 ]]; then
      echo "missing shell command" >&2
      exit 64
    fi
    shell_command="$*"$'\n''exit'
    run_adb shell "$shell_command" </dev/null
    status=$?
    ;;
  *)
    shell_command="$*"$'\n''exit'
    run_adb shell "$shell_command" </dev/null
    status=$?
    ;;
esac

if [[ "$status" -eq 124 ]]; then
  echo "ADB command timed out after ${TIMEOUT_SECONDS}s" >&2
  echo "If stdout contains the requested value, treat it as usable partial output before retrying." >&2
fi
exit "$status"
''';

const String _androidDynamicProbeScript =
    r'''#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADB_ONE_SHOT="${ADB_ONE_SHOT:-$SCRIPT_DIR/adb_one_shot.sh}"
''' +
    _androidAdbProbeArguments +
    _boundedShellTimeoutFunction +
    _androidAdbQuickShellFunctions +
    r'''
run_section() {
  section "$1"
  shift
  "$@" 2>&1
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    printf '(exit=%s)\n' "$status"
  fi
}

valid_package() {
  [[ "$PACKAGE_NAME" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]]
}

section metadata
printf 'serial=%s\n' "${SERIAL:-auto}"
printf 'package=%s\n' "${PACKAGE_NAME:-unset}"
printf 'timeout_seconds=%s\n' "$TIMEOUT_SECONDS"

run_section adb_devices "$ADB_BIN" devices -l
run_section adb_get_state adb_quick get-state
run_section adb_shell_ping adb_quick shell true
run_section device_abi adb_quick shell getprop ro.product.cpu.abi
run_section device_sdk adb_quick shell getprop ro.build.version.sdk
run_section adb_forwards adb_quick forward --list
run_section adb_reverses adb_quick reverse --list

if valid_package; then
  run_section package_path adb_quick shell "pm path $PACKAGE_NAME"
  run_section launcher_resolve adb_quick shell "cmd package resolve-activity --brief $PACKAGE_NAME"
  run_section package_pid adb_quick shell "pidof $PACKAGE_NAME"
  run_section foreground adb_quick shell "dumpsys window | grep -E 'mCurrentFocus|mFocusedApp' | head -6"
  section package_logcat_tail
  adb_quick logcat -d -v time -t 220 2>&1 | grep -i -- "$PACKAGE_NAME" | tail -80 || true
else
  section package_checks
  echo "package is unset or invalid; pass -p <package.name> to enable package checks"
fi

section frida_cli
if command -v frida >/dev/null 2>&1; then
  frida --version 2>&1
else
  echo "frida not found"
fi

section frida_server
adb_quick shell "pidof frida-server || ps -A | grep frida || ls -l /data/local/tmp/frida* 2>/dev/null || true" 2>&1

section frida_ps
if command -v frida-ps >/dev/null 2>&1; then
  run_with_timeout frida-ps -Uai 2>&1 | head -120
else
  echo "frida-ps not found"
fi
''';

const String _deviceReportSnapshotScript = r'''
printf '[identity]\n'
getprop ro.serialno
getprop ro.boot.serialno
getprop ro.product.manufacturer
getprop ro.product.model
getprop ro.build.version.release
getprop ro.build.version.sdk
printf '[battery]\n'
dumpsys battery | grep -E 'level:|status:|temperature:|voltage:|AC powered:|USB powered:|Wireless powered:' || true
printf '[display]\n'
wm size
wm density
printf '[storage]\n'
df -h /data /sdcard /system 2>/dev/null || df /data /sdcard /system 2>/dev/null || true
printf '[network]\n'
ip -o addr show 2>/dev/null | grep -E 'inet ' || true
settings get global http_proxy 2>/dev/null || true
printf '[foreground]\n'
dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -6 || true
printf '[process_sample]\n'
ps -A 2>/dev/null | head -80 || ps 2>/dev/null | head -80 || true
printf '[disabled_packages]\n'
pm list packages -d 2>/dev/null | head -80 || true
''';

const String _staticQuickScanScript = r'''
set +e
mkdir -p "$OUT_DIR"
cd "$OUT_DIR" || exit 2
: > badging.txt
: > manifest.txt
: > components.txt
: > certs.txt
: > zip_listing.txt
: > nested_apks.txt
: > flutter.txt
: > native_libs.txt
: > suspicious_files.txt
: > SUMMARY.md
: > network_candidates.txt
: > business_urls.txt
: > business_domains.txt
: > business_network_sources.txt
: > urls.txt
: > domains.txt
: > ips.txt
: > network_sources.txt
: > interesting_strings.txt
: > _apk_entries.txt

AAPT="$(command -v aapt || true)"
if [ -z "$AAPT" ] && [ -d "$HOME/Library/Android/sdk/build-tools" ]; then
  AAPT="$(find "$HOME/Library/Android/sdk/build-tools" -name aapt -type f 2>/dev/null | sort -r | head -1)"
fi
if [ -n "$AAPT" ] && [ -x "$AAPT" ]; then
  "$AAPT" dump badging "$APK_PATH" > badging.txt 2>&1
  "$AAPT" dump xmltree "$APK_PATH" AndroidManifest.xml > manifest.txt 2>&1
  grep -aEi 'uses-permission|activity|service|receiver|provider|intent-filter|action|category|data' manifest.txt | head -500 > components.txt
else
  echo "aapt not found" > badging.txt
  echo "aapt not found" > manifest.txt
  echo "aapt not found" > components.txt
fi

APKSIGNER="$(command -v apksigner || true)"
if [ -z "$APKSIGNER" ] && [ -d "$HOME/Library/Android/sdk/build-tools" ]; then
  APKSIGNER="$(find "$HOME/Library/Android/sdk/build-tools" -name apksigner -type f 2>/dev/null | sort -r | head -1)"
fi
if [ -n "$APKSIGNER" ] && [ -x "$APKSIGNER" ]; then
  "$APKSIGNER" verify --print-certs "$APK_PATH" > certs.txt 2>&1
else
  echo "apksigner not found" > certs.txt
fi

UNZIP="$(command -v unzip || true)"
if [ -n "$UNZIP" ] && [ -x "$UNZIP" ]; then
  "$UNZIP" -l "$APK_PATH" > zip_listing.txt 2>&1
  "$UNZIP" -Z1 "$APK_PATH" 2>/dev/null > _apk_entries.txt
  grep -aEi '\.apk$' _apk_entries.txt | head -20 > nested_apks.txt
  grep -aE '^lib/[^/]+/[^/]+\.so$' _apk_entries.txt | sort -u > native_libs.txt
  {
    grep -aE '^lib/[^/]+/libflutter\.so$' _apk_entries.txt | sed 's/^/flutter_engine: /'
    grep -aE '^lib/[^/]+/libapp\.so$' _apk_entries.txt | sed 's/^/flutter_dart_aot: /'
    grep -aE '^assets/flutter_assets/' _apk_entries.txt | head -80 | sed 's/^/flutter_asset: /'
  } > flutter.txt
  [ -s flutter.txt ] || echo "(no Flutter markers found)" > flutter.txt
  grep -aEi 'signaturekiller|jiagu|secneo|bangcle|ijiami|dexprotector|packer|protect|origin.*\.apk|\.apk$|frida|xposed|substrate|reflutter|libapp\.so|libflutter\.so' _apk_entries.txt | sort -u > suspicious_files.txt
else
  echo "unzip not found" > zip_listing.txt
  echo "unzip not found" > flutter.txt
  echo "unzip not found" > native_libs.txt
  echo "unzip not found" > suspicious_files.txt
fi

STRINGS="$(command -v strings || xcrun -find strings 2>/dev/null || true)"
if [ -n "$STRINGS" ] && [ -x "$STRINGS" ]; then
  run_strings() {
    "$STRINGS" -n 6 "$@" 2>/dev/null
  }
  HOST_PATTERN='([A-Za-z][A-Za-z0-9-]*\.)+(com|net|org|cn|io|vip|top|xyz|app|dev|co|cc|tv|me|info|biz|pro|shop|site|online|cloud|tech|live|link|icu|ink|work|fun|club|store|ai|one|run|today|world|website|space|gov|edu|mil|int|jp|kr|us|uk|de|fr|ru|br|in|au|ca|hk|tw|sg)'
  {
    if [ -n "$UNZIP" ] && [ -x "$UNZIP" ]; then
      "$UNZIP" -p "$APK_PATH" "lib/*/*.so" 2>/dev/null | run_strings
      "$UNZIP" -p "$APK_PATH" "classes*.dex" 2>/dev/null | run_strings
      "$UNZIP" -Z1 "$APK_PATH" 2>/dev/null | grep -aE '^assets/.*\.(apk|json|txt|xml|properties|conf|ini|html|js)$' | head -120 | while IFS= read -r asset_entry; do
        "$UNZIP" -p "$APK_PATH" "$asset_entry" 2>/dev/null | run_strings
      done
      if [ -s nested_apks.txt ]; then
        rm -rf _nested_apks_tmp
        mkdir -p _nested_apks_tmp
        while IFS= read -r nested_apk; do
          safe_name="$(printf '%s' "$nested_apk" | tr '/ ' '__' | tr -cd 'A-Za-z0-9_.-')"
          nested_path="_nested_apks_tmp/${safe_name:-nested.apk}"
          "$UNZIP" -p "$APK_PATH" "$nested_apk" > "$nested_path" 2>/dev/null
          "$UNZIP" -p "$nested_path" "lib/*/*.so" 2>/dev/null | run_strings
          "$UNZIP" -p "$nested_path" "classes*.dex" 2>/dev/null | run_strings
          "$UNZIP" -Z1 "$nested_path" 2>/dev/null | grep -aE '^assets/.*\.(json|txt|xml|properties|conf|ini|html|js)$' | head -80 | while IFS= read -r nested_asset; do
            "$UNZIP" -p "$nested_path" "$nested_asset" 2>/dev/null | run_strings
          done
        done < nested_apks.txt
        rm -rf _nested_apks_tmp
      fi
    else
      run_strings "$APK_PATH"
    fi
  } | LC_ALL=C awk 'length($0) <= 4096' | head -60000 > all_strings.txt
  NOISE_DOMAIN_PATTERN='android\.com|android\.googlesource\.com|w3\.org|google\.com|g\.co|gstatic\.com|googleapis\.com|firebaseio\.com|firebase\.google\.com|github\.com|githubusercontent\.com|schema\.org|apache\.org|mozilla\.org|gradle\.org|dashif\.org|adobe\.com|ns\.adobe\.com|ietf\.org|iana\.org|unicode\.org|kotlinlang\.org|jetbrains\.com|dart\.dev|api\.flutter\.dev|flutter\.dev|flutter\.io|plugins\.flutter\.io|flutter\.baseflow\.com|pub\.dev|ibm\.com|www\.ibm\.com|vnd\.|cloudflare\.com|cloudfront\.net|facebook\.com|fbcdn\.net|appsflyer\.com|adjust\.com|umeng\.com|bugly\.qq\.com|qq\.com|tencent\.com|baidu\.com|aliyun\.com|huawei\.com|xiaomi\.com'
  LC_ALL=C awk '{ line=$0; while (match(line, /https?:\/\/[^[:space:]]+/)) { print substr(line, RSTART, RLENGTH); line=substr(line, RSTART+RLENGTH) } }' all_strings.txt | LC_ALL=C sed "s/[),;\"'<>}]*$//" | LC_ALL=C sort -u | head -500 > urls.txt
  {
    LC_ALL=C grep -aEio "\b$HOST_PATTERN\b" all_strings.txt
    LC_ALL=C sed -n 's#^[A-Za-z][A-Za-z0-9+.-]*://\([^/:?#]*\).*#\1#p' urls.txt
  } | tr '[:upper:]' '[:lower:]' | LC_ALL=C grep -aviE "$NOISE_DOMAIN_PATTERN|\.(png|jpg|jpeg|webp|gif|svg|ttf|otf|xml|json|html|js|css|so|dex|apk|zip)$" | LC_ALL=C sort -u | head -500 > domains.txt
  LC_ALL=C grep -aviE "$NOISE_DOMAIN_PATTERN|/schemas?/|/guidelines?/|/licenses?/|\.xsd($|[?#])|\.dtd($|[?#])|\.css($|[?#])|\.js($|[?#])|\.png($|[?#])|\.jpg($|[?#])|\.jpeg($|[?#])|\.webp($|[?#])|\.gif($|[?#])|\.svg($|[?#])|\.ttf($|[?#])|\.otf($|[?#])" urls.txt | head -200 > business_urls.txt
  LC_ALL=C grep -aviE "$NOISE_DOMAIN_PATTERN" domains.txt | head -200 > business_domains.txt
  LC_ALL=C grep -aEio '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' all_strings.txt | LC_ALL=C sort -u | head -200 > ips.txt
  LC_ALL=C grep -aEi 'https?://|sign|encrypt|token|secret|okhttp|retrofit|webview|ssl|certificate|api|host|domain' all_strings.txt | LC_ALL=C sort -u | head -500 > interesting_strings.txt
  if [ -n "$UNZIP" ] && [ -x "$UNZIP" ] && [ -s _apk_entries.txt ]; then
    rm -rf _network_sources_tmp
    mkdir -p _network_sources_tmp
    {
      grep -aE '^lib/[^/]+/[^/]+\.so$' _apk_entries.txt
      grep -aE '^classes[0-9]*\.dex$' _apk_entries.txt
      grep -aE '^(assets|res/raw)/.*\.(apk|json|txt|xml|properties|conf|ini|html|js)$' _apk_entries.txt
    } | awk '!seen[$0]++' | head -220 | while IFS= read -r entry; do
      safe_entry="$(printf '%s' "$entry" | tr '/ ' '__' | tr -cd 'A-Za-z0-9_.-')"
      entry_strings="_network_sources_tmp/${safe_entry:-entry}.txt"
      "$UNZIP" -p "$APK_PATH" "$entry" 2>/dev/null | run_strings | LC_ALL=C awk 'length($0) <= 4096' > "$entry_strings"
      {
        LC_ALL=C awk 'index($0, "http://") || index($0, "https://")' "$entry_strings"
        LC_ALL=C grep -aEi "$HOST_PATTERN|okhttp|retrofit|host|domain|api|graphql|socket|websocket|mqtt|sign|token|encrypt" "$entry_strings" | LC_ALL=C grep -aviE '\.(png|jpg|jpeg|webp|gif|svg|ttf|otf)$'
      } | LC_ALL=C awk '!seen[$0]++' | head -120 | awk -v entry="$entry" '{print entry ":" $0}'
    done | LC_ALL=C awk 'length($0) <= 4096' | head -1500 > network_sources.txt
    if [ -s business_domains.txt ]; then
      while IFS= read -r business_domain; do
        LC_ALL=C grep -aFi "$business_domain" network_sources.txt
      done < business_domains.txt | LC_ALL=C sort -u > business_network_sources.txt
    fi
    {
      LC_ALL=C grep -aEi '(^|[[:space:]:])/(api|activity|domain|front|login|member|sign|token|user)[A-Za-z0-9_./?=&-]*' network_sources.txt
      LC_ALL=C grep -aEi 'CDNHOST|domain_file_cdn' network_sources.txt
    } | LC_ALL=C grep -aviE "$NOISE_DOMAIN_PATTERN|dev\.flutter|dart\.|pigeon|PlatformConfiguration|Canvas::|Socket|application/|text/|vnd\.|Select|Seleccion|tapiwch|caratteri|headline|ChangeNotifier|Float64|NoSuchMethod|databaseFactory" >> business_network_sources.txt
    LC_ALL=C sort -u business_network_sources.txt | head -400 > _business_network_sources.tmp
    mv _business_network_sources.tmp business_network_sources.txt
    rm -rf _network_sources_tmp
  fi
  {
    if [ -s business_urls.txt ]; then sed 's/^/url: /' business_urls.txt; fi
    if [ -s business_domains.txt ]; then sed 's/^/domain: /' business_domains.txt; fi
    if [ -s business_network_sources.txt ]; then sed 's/^/source: /' business_network_sources.txt; fi
    if [ -s ips.txt ]; then sed 's/^/ip: /' ips.txt; fi
  } | LC_ALL=C awk '!seen[$0]++' | head -500 > network_candidates.txt
else
  echo "strings not found" > interesting_strings.txt
  echo "strings not found" > network_sources.txt
fi

{
  printf '# Android reverse quick scan summary\n\n'
  printf '%s\n' "- generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\n\n' "- apk: $APK_PATH"
  printf '## Top network candidates\n\n'
  if [ -s network_candidates.txt ]; then
    sed -n '1,80p' network_candidates.txt
  else
    printf '(empty)\n'
  fi
  printf '\n## Business URLs\n\n'
  if [ -s business_urls.txt ]; then
    sed -n '1,80p' business_urls.txt
  else
    printf '(empty)\n'
  fi
  printf '\n## Business domains\n\n'
  if [ -s business_domains.txt ]; then
    sed -n '1,80p' business_domains.txt
  else
    printf '(empty)\n'
  fi
  printf '\n## Network evidence sources\n\n'
  if [ -s business_network_sources.txt ]; then
    sed -n '1,120p' business_network_sources.txt
  else
    printf '(empty)\n'
  fi
  printf '\n## App shape\n\n'
  sed -n '1,40p' flutter.txt 2>/dev/null || true
  sed -n '1,40p' suspicious_files.txt 2>/dev/null || true
  printf '\n## Guidance\n\n'
  printf '%s\n' '- If business URL/domain candidates are present, report the static conclusion before dynamic validation.'
  printf '%s\n' '- Use Frida or mitmproxy only for runtime-only parameters or optional validation.'
} > SUMMARY.md

printf 'quick scan completed\n'
''';

const String _staticQuickScanReadScript = r'''
set +e
cd "$QUICK_SCAN_DIR" || exit 2
printf 'quick_scan_dir=%s\n' "$QUICK_SCAN_DIR"
for name in SUMMARY.md network_candidates.txt business_urls.txt business_domains.txt business_network_sources.txt network_sources.txt urls.txt domains.txt ips.txt interesting_strings.txt flutter.txt native_libs.txt suspicious_files.txt nested_apks.txt certs.txt components.txt; do
  printf '\n[%s]\n' "$name"
  if [ -s "$name" ]; then
    sed -n '1,140p' "$name"
  elif [ -e "$name" ]; then
    printf '(empty)\n'
  else
    printf '(missing)\n'
  fi
done
''';

const String _staticApkIdentityScript = r'''
set +e
mkdir -p "$OUT_DIR"
find_build_tool() {
  local name="$1"
  local path
  path="$(command -v "$name" 2>/dev/null || true)"
  if [ -z "$path" ] && [ -d "$HOME/Library/Android/sdk/build-tools" ]; then
    path="$(find "$HOME/Library/Android/sdk/build-tools" -name "$name" -type f 2>/dev/null | sort -r | head -1)"
  fi
  printf '%s' "$path"
}
AAPT="$(find_build_tool aapt)"
APKSIGNER="$(find_build_tool apksigner)"
printf '[apk]\n'
printf 'path=%s\n' "$APK_PATH"
ls -lh "$APK_PATH" 2>&1
printf '\n[output]\n%s\n' "$OUT_DIR"
printf '\n[badging]\n'
if [ -n "$AAPT" ] && [ -x "$AAPT" ]; then
  "$AAPT" dump badging "$APK_PATH" > "$OUT_DIR/badging.txt" 2>&1
  sed -n '1,80p' "$OUT_DIR/badging.txt"
  "$AAPT" dump xmltree "$APK_PATH" AndroidManifest.xml > "$OUT_DIR/manifest.txt" 2>&1
  grep -aEi 'package=|versionName|sdkVersion|targetSdkVersion|uses-permission|activity|service|receiver|provider|networkSecurityConfig|usesCleartextTraffic' "$OUT_DIR/manifest.txt" | head -220 > "$OUT_DIR/manifest_summary.txt"
  printf '\n[manifest_summary]\n'
  sed -n '1,220p' "$OUT_DIR/manifest_summary.txt"
else
  printf 'aapt not found\n'
fi
printf '\n[certificates]\n'
if [ -n "$APKSIGNER" ] && [ -x "$APKSIGNER" ]; then
  "$APKSIGNER" verify --print-certs "$APK_PATH" > "$OUT_DIR/certs.txt" 2>&1
  sed -n '1,140p' "$OUT_DIR/certs.txt"
else
  printf 'apksigner not found\n'
fi
''';

const String _staticJadxScript = r'''
set +e
JADX="$(command -v jadx 2>/dev/null || true)"
if [ -z "$JADX" ]; then
  printf 'jadx not found\n' >&2
  exit 127
fi
mkdir -p "$OUT_DIR"
printf 'output=%s\n' "$OUT_DIR"
"$JADX" -d "$OUT_DIR/src" "$APK_PATH" > "$OUT_DIR/jadx.log" 2>&1
status=$?
printf 'exit=%s\n' "$status"
printf '\n[jadx_log]\n'
sed -n '1,160p' "$OUT_DIR/jadx.log"
printf '\n[network_crypto_hits]\n'
grep -RInE 'https?://|sign|encrypt|token|secret|okhttp|retrofit|certificate|ssl|Cipher|Mac\.getInstance|MessageDigest' "$OUT_DIR/src" 2>/dev/null | head -240 > "$OUT_DIR/network_crypto_hits.txt"
if [ -s "$OUT_DIR/network_crypto_hits.txt" ]; then
  sed -n '1,240p' "$OUT_DIR/network_crypto_hits.txt"
else
  printf '(empty)\n'
fi
exit "$status"
''';

const String _staticApktoolScript = r'''
set +e
APKTOOL="$(command -v apktool 2>/dev/null || true)"
if [ -z "$APKTOOL" ]; then
  printf 'apktool not found\n' >&2
  exit 127
fi
mkdir -p "$OUT_DIR"
printf 'output=%s\n' "$OUT_DIR"
"$APKTOOL" d -f "$APK_PATH" -o "$OUT_DIR/unpacked" > "$OUT_DIR/apktool.log" 2>&1
status=$?
printf 'exit=%s\n' "$status"
printf '\n[apktool_log]\n'
sed -n '1,160p' "$OUT_DIR/apktool.log"
printf '\n[manifest]\n'
if [ -f "$OUT_DIR/unpacked/AndroidManifest.xml" ]; then
  grep -aEi 'package=|permission|activity|service|receiver|provider|networkSecurityConfig|usesCleartextTraffic' "$OUT_DIR/unpacked/AndroidManifest.xml" | head -180
else
  printf '(missing)\n'
fi
printf '\n[smali_hits]\n'
grep -RInE 'invoke-.*(sign|encrypt|token)|https?://|Cipher|MessageDigest|Mac;' "$OUT_DIR/unpacked/smali"* 2>/dev/null | head -240 > "$OUT_DIR/smali_hits.txt"
if [ -s "$OUT_DIR/smali_hits.txt" ]; then
  sed -n '1,240p' "$OUT_DIR/smali_hits.txt"
else
  printf '(empty)\n'
fi
exit "$status"
''';

const String _staticStringsScript = r'''
set +e
mkdir -p "$OUT_DIR"
STRINGS="$(command -v strings 2>/dev/null || xcrun -find strings 2>/dev/null || true)"
UNZIP="$(command -v unzip 2>/dev/null || true)"
if [ -z "$STRINGS" ]; then
  printf 'strings not found\n' >&2
  exit 127
fi
printf 'output=%s\n' "$OUT_DIR"
if [ -n "$UNZIP" ]; then
  "$UNZIP" -p "$APK_PATH" 'classes*.dex' 'lib/*/*.so' 'assets/*' 2>/dev/null | "$STRINGS" -n 6 2>/dev/null | awk 'length($0) <= 4096' | head -60000 > "$OUT_DIR/all_strings.txt"
  "$UNZIP" -Z1 "$APK_PATH" 2>/dev/null | grep -aE '\.so$|assets/|\.dex$|\.apk$' | head -400 > "$OUT_DIR/apk_entries.txt"
else
  "$STRINGS" -n 6 "$APK_PATH" 2>/dev/null | awk 'length($0) <= 4096' | head -60000 > "$OUT_DIR/all_strings.txt"
  : > "$OUT_DIR/apk_entries.txt"
fi
grep -aEio 'https?://[^[:space:]"<>)]+' "$OUT_DIR/all_strings.txt" | sed 's/[),;]*$//' | sort -u | head -400 > "$OUT_DIR/urls.txt"
grep -aEio '\b([A-Za-z][A-Za-z0-9-]*\.)+(com|net|org|cn|io|app|dev|cloud|top|vip|xyz|ai|run|site|online|shop|tech|jp|kr|us|uk|de|fr|ru|br|in|au|ca|hk|tw|sg)\b' "$OUT_DIR/all_strings.txt" | tr '[:upper:]' '[:lower:]' | sort -u | head -400 > "$OUT_DIR/domains.txt"
grep -aEi 'sign|encrypt|decrypt|token|secret|apikey|authorization|okhttp|retrofit|graphql|websocket|ssl|certificate|Cipher|MessageDigest|Hmac|AES|RSA|SHA-256|MD5' "$OUT_DIR/all_strings.txt" | sort -u | head -500 > "$OUT_DIR/crypto_network_terms.txt"
printf '\n[urls]\n'
sed -n '1,160p' "$OUT_DIR/urls.txt"
printf '\n[domains]\n'
sed -n '1,160p' "$OUT_DIR/domains.txt"
printf '\n[crypto_network_terms]\n'
sed -n '1,220p' "$OUT_DIR/crypto_network_terms.txt"
printf '\n[entries]\n'
sed -n '1,120p' "$OUT_DIR/apk_entries.txt"
''';

const String _networkCaptureReadScript = r'''
set +e
printf '[network_jsonl]\n'
printf 'path=%s\n' "$NETWORK_JSONL"
if [ -s "$NETWORK_JSONL" ]; then
  tail -n "${TAIL_LINES:-120}" "$NETWORK_JSONL"
else
  printf '(empty)\n'
fi
printf '\n[flows]\n'
ls -lh "$NETWORK_DIR"/flows.mitm "$NETWORK_DIR"/flows.txt 2>/dev/null || true
if [ -s "$NETWORK_DIR/flows.txt" ]; then
  printf '\n[flows_text]\n'
  sed -n '1,220p' "$NETWORK_DIR/flows.txt"
fi
''';

const String _networkCaptureExportScript = r'''
set +e
FLOWS="$NETWORK_DIR/flows.mitm"
TEXT="$NETWORK_DIR/flows.txt"
if [ ! -s "$FLOWS" ]; then
  printf 'mitmproxy flow file not found: %s\n' "$FLOWS" >&2
  exit 2
fi
MITMDUMP="$(command -v mitmdump 2>/dev/null || true)"
if [ -z "$MITMDUMP" ]; then
  printf 'mitmdump not found\n' >&2
  exit 127
fi
"$MITMDUMP" -nr "$FLOWS" > "$TEXT" 2>&1
status=$?
printf 'flows_text=%s\n' "$TEXT"
printf 'exit=%s\n' "$status"
printf '\n[preview]\n'
sed -n '1,220p' "$TEXT"
exit "$status"
''';

const String _certificateArtifactsReadScript = r'''
set +e
printf 'certs_dir=%s\n' "$CERTS_DIR"
for name in README.md res/xml/network_security_config.xml AndroidManifest.application.xml install_mitm_ca_root.sh generate_debug_keystore.sh sign_repacked_apk.sh verify_apk_signature.sh; do
  printf '\n[%s]\n' "$name"
  path="$CERTS_DIR/$name"
  if [ -s "$path" ]; then
    sed -n '1,220p' "$path"
  elif [ -e "$path" ]; then
    printf '(empty)\n'
  else
    printf '(missing)\n'
  fi
done
''';

const String _mitmproxyCaInspectScript = r'''
set +e
CERT_PATH="${MITM_CERT_PATH:-$HOME/.mitmproxy/mitmproxy-ca-cert.pem}"
printf 'cert_path=%s\n' "$CERT_PATH"
if [ ! -s "$CERT_PATH" ]; then
  printf 'mitmproxy CA not found: %s\n' "$CERT_PATH" >&2
  exit 2
fi
OPENSSL="$(command -v openssl 2>/dev/null || true)"
if [ -z "$OPENSSL" ]; then
  printf 'openssl not found\n' >&2
  exit 127
fi
printf '\n[hash]\n'
"$OPENSSL" x509 -inform PEM -subject_hash_old -in "$CERT_PATH" | head -1
printf '\n[subject]\n'
"$OPENSSL" x509 -inform PEM -in "$CERT_PATH" -noout -subject -issuer -dates -fingerprint -sha256
''';

const String _mitmproxyJsonlAddon = r'''
import base64
import hashlib
import json
import os
import time
from pathlib import Path

from mitmproxy import http

OUT_PATH = Path(
    os.environ.get("OPENHAND_NETWORK_JSONL")
    or Path(__file__).with_name("network.jsonl")
)
MAX_BODY_PREVIEW = int(os.environ.get("OPENHAND_BODY_PREVIEW_BYTES", "4096"))


def _headers(headers):
    return {str(k): str(v) for k, v in headers.items()}

def _body_preview(raw):
    if not raw:
        return None
    clipped = raw[:MAX_BODY_PREVIEW]
    truncated = len(raw) > len(clipped)
    try:
        return {
            "encoding": "utf-8",
            "truncated": truncated,
            "value": clipped.decode("utf-8"),
        }
    except UnicodeDecodeError:
        return {
            "encoding": "base64",
            "truncated": truncated,
            "value": base64.b64encode(clipped).decode("ascii"),
        }

def _write(record):
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
        fh.write("\n")


def response(flow: http.HTTPFlow):
    request = flow.request
    response = flow.response
    req_body = request.raw_content or b""
    resp_body = response.raw_content or b""
    record = {
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "method": request.method,
        "scheme": request.scheme,
        "host": request.host,
        "port": request.port,
        "path": request.path,
        "url": request.pretty_url,
        "status_code": response.status_code,
        "reason": response.reason,
        "request_headers": _headers(request.headers),
        "response_headers": _headers(response.headers),
        "request_body_sha256": hashlib.sha256(req_body).hexdigest()
        if req_body
        else None,
        "response_body_sha256": hashlib.sha256(resp_body).hexdigest()
        if resp_body
        else None,
        "request_body_preview": _body_preview(req_body),
        "response_body_preview": _body_preview(resp_body),
    }
    _write(record)


def error(flow: http.HTTPFlow):
    request = flow.request
    record = {
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "method": request.method if request else None,
        "host": request.host if request else None,
        "url": request.pretty_url if request else None,
        "error": str(flow.error) if flow.error else "unknown",
    }
    _write(record)
''';

const String _networkCaptureReadme = '''# Android reverse network capture

Use this directory for mitmproxy capture output and proxy diagnostics.

Files:
- openhand_mitm_jsonl.py: mitmproxy addon that writes compact HTTP records.
- ../network.jsonl: structured request / response summaries.
- flows.mitm: full mitmproxy flow file when capture is started with `-w`.
- flows.txt: optional text export from `mitmdump -nr flows.mitm`.
- proxy_probe.sh: ADB proxy / package / certificate failure preflight.

Workflow:
1. Generate certificate artifacts from the Certs tab before HTTPS capture.
2. Start mitmproxy with `OPENHAND_NETWORK_JSONL=<session>/network.jsonl mitmdump -p 8080 -s openhand_mitm_jsonl.py -w flows.mitm`.
3. Set the device proxy to `<host-ip>:8080`, then run `proxy_probe.sh`.
4. Launch or exercise the target app, then read `../network.jsonl` first.
5. If `network.jsonl` is empty, inspect proxy status, CA trust, SSL pinning, and logcat TLS errors before retrying.

Stop rules:
- Do not keep toggling proxy settings blindly; capture proxy state before changing it.
- Clear the global proxy when the capture is finished.
- If static quick_scan already proves one business domain or URL, deliver the conclusion first; network capture is optional validation.
''';

const String _networkProxyProbeScript =
    r'''#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADB_ONE_SHOT="${ADB_ONE_SHOT:-$SESSION_DIR/scripts/adb_one_shot.sh}"
''' +
    _androidAdbProbeArguments +
    _boundedShellTimeoutFunction +
    _androidAdbQuickShellFunctions +
    r'''
valid_package() {
  [[ "$PACKAGE_NAME" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$ ]]
}

section metadata
printf 'serial=%s\n' "${SERIAL:-auto}"
printf 'package=%s\n' "${PACKAGE_NAME:-unset}"
printf 'timeout_seconds=%s\n' "$TIMEOUT_SECONDS"
printf 'network_jsonl=%s\n' "$SESSION_DIR/network.jsonl"

section adb_devices
"$ADB_BIN" devices -l 2>&1

section device_proxy
adb_quick shell "settings get global http_proxy; settings get global global_http_proxy_host 2>/dev/null; settings get global global_http_proxy_port 2>/dev/null" 2>&1

section device_network
adb_quick shell "ip route 2>/dev/null | head -20; ip -o addr show 2>/dev/null | grep -E 'inet ' | head -40" 2>&1

section package_permissions
if valid_package; then
  adb_quick shell "dumpsys package $PACKAGE_NAME | grep -Ei 'versionName|targetSdk|android.permission.INTERNET|networkSecurityConfig|usesCleartextTraffic' | head -80" 2>&1
else
  echo "package is unset or invalid; pass -p <package.name> to enable package checks"
fi

section logcat_tls_tail
if valid_package; then
  adb_quick logcat -d -v time -t 320 2>&1 | grep -Ei "$PACKAGE_NAME|SSLHandshake|CertPath|Trust anchor|CLEARTEXT|UnknownHost|ConnectException|proxy|mitm" | tail -120 || true
else
  adb_quick logcat -d -v time -t 220 2>&1 | grep -Ei "SSLHandshake|CertPath|Trust anchor|CLEARTEXT|UnknownHost|ConnectException|proxy|mitm" | tail -80 || true
fi

section local_capture_files
ls -lh "$SCRIPT_DIR" "$SESSION_DIR/network.jsonl" 2>/dev/null || true
''';

const String _reproduceScriptsReadme = '''# Android reverse reproduction scripts

This directory stores final runnable reproductions and evidence bundles.

Files:
- reproduce_http.py: Python HTTP replay template. Uses requests when present, with urllib fallback.
- reproduce_curl.sh: curl replay template using HEADERS_FILE / BODY_FILE.
- make_evidence_bundle.sh: local artifact summary for final delivery.
- adb_one_shot.sh: short-timeout ADB helper.
- android_dynamic_probe.sh: ADB / launcher / Frida preflight.

Workflow:
1. Fill TARGET_URL, HTTP_METHOD, HEADERS_FILE or HEADERS_JSON, and BODY_FILE from Frida/network evidence.
2. Run reproduce_http.py and reproduce_curl.sh without an IDE.
3. Compare key response fields with `network.jsonl` or Frida output.
4. Run make_evidence_bundle.sh and include the generated Markdown path in the final answer.

Rules:
- Do not store real long-lived secrets in committed templates.
- Keep one reproduction per endpoint or scenario.
- Note token/cookie expiry windows at the top of the final script.
''';

const String _reproduceHttpPythonScript = '''#!/usr/bin/env python3
"""Minimal Android reverse HTTP reproduction template.

Set environment variables before running:
  TARGET_URL       required, full URL
  HTTP_METHOD      optional, default GET
  HEADERS_JSON     optional, JSON object of headers
  HEADERS_FILE     optional, one `Header: value` line per header
  BODY             optional, request body text
  BODY_FILE        optional, request body file path
  TIMEOUT_SECONDS  optional, default 20

The script uses requests when installed and falls back to urllib.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request


def _load_headers() -> dict[str, str]:
    headers: dict[str, str] = {}
    headers_json = os.environ.get("HEADERS_JSON", "").strip()
    if headers_json:
        value = json.loads(headers_json)
        if not isinstance(value, dict):
            raise SystemExit("HEADERS_JSON must be a JSON object")
        headers.update({str(k): str(v) for k, v in value.items()})
    headers_file = os.environ.get("HEADERS_FILE", "").strip()
    if headers_file:
        with open(headers_file, "r", encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if ":" not in line:
                    raise SystemExit(f"invalid header line: {line}")
                key, value = line.split(":", 1)
                headers[key.strip()] = value.strip()
    return headers


def _load_body() -> bytes | None:
    body_file = os.environ.get("BODY_FILE", "").strip()
    if body_file:
        with open(body_file, "rb") as fh:
            return fh.read()
    body = os.environ.get("BODY")
    if body is not None:
        return body.encode("utf-8")
    return None


def _print_response(status: int, headers: dict[str, str], body: bytes) -> None:
    print(f"status={status}")
    print("headers=" + json.dumps(headers, ensure_ascii=False, sort_keys=True))
    text = body.decode("utf-8", errors="replace")
    print(text)


def _run_with_requests(
    method: str,
    url: str,
    headers: dict[str, str],
    body: bytes | None,
    timeout: float,
) -> bool:
    try:
        import requests  # type: ignore
    except Exception:
        return False
    response = requests.request(
        method,
        url,
        headers=headers,
        data=body,
        timeout=timeout,
    )
    _print_response(response.status_code, dict(response.headers), response.content)
    return True


def _run_with_urllib(
    method: str,
    url: str,
    headers: dict[str, str],
    body: bytes | None,
    timeout: float,
) -> None:
    request = urllib.request.Request(
        url,
        data=body,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            _print_response(
                response.status,
                dict(response.headers.items()),
                response.read(),
            )
    except urllib.error.HTTPError as error:
        _print_response(error.code, dict(error.headers.items()), error.read())
        raise SystemExit(1)


def main() -> int:
    url = os.environ.get("TARGET_URL", "").strip()
    if not url:
        print("TARGET_URL is required", file=sys.stderr)
        return 64
    method = os.environ.get("HTTP_METHOD", "GET").strip().upper() or "GET"
    timeout = float(os.environ.get("TIMEOUT_SECONDS", "20"))
    headers = _load_headers()
    body = _load_body()
    if _run_with_requests(method, url, headers, body, timeout):
        return 0
    _run_with_urllib(method, url, headers, body, timeout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
''';

const String _reproduceCurlScript = r'''#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="${TARGET_URL:-}"
HTTP_METHOD="${HTTP_METHOD:-GET}"
HEADERS_FILE="${HEADERS_FILE:-}"
BODY_FILE="${BODY_FILE:-}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-20}"

if [[ -z "$TARGET_URL" ]]; then
  echo "TARGET_URL is required" >&2
  exit 64
fi

args=(-i -sS --max-time "$TIMEOUT_SECONDS" -X "$HTTP_METHOD")

if [[ -n "$HEADERS_FILE" ]]; then
  if [[ ! -f "$HEADERS_FILE" ]]; then
    echo "HEADERS_FILE not found: $HEADERS_FILE" >&2
    exit 66
  fi
  while IFS= read -r header_line || [[ -n "$header_line" ]]; do
    [[ -z "${header_line// }" || "${header_line:0:1}" == "#" ]] && continue
    args+=(-H "$header_line")
  done < "$HEADERS_FILE"
fi

if [[ -n "$BODY_FILE" ]]; then
  if [[ ! -f "$BODY_FILE" ]]; then
    echo "BODY_FILE not found: $BODY_FILE" >&2
    exit 66
  fi
  args+=(--data-binary "@$BODY_FILE")
fi

curl "${args[@]}" "$TARGET_URL"
''';

const String _evidenceBundleScript = r'''#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$SCRIPT_DIR/evidence_bundle_$STAMP.md"

section() {
  printf '\n## %s\n\n' "$1" >> "$OUT"
}

fence_file() {
  local path="$1"
  local lines="${2:-120}"
  if [[ -f "$path" ]]; then
    printf '```text\n' >> "$OUT"
    tail -n "$lines" "$path" >> "$OUT"
    printf '\n```\n' >> "$OUT"
  else
    printf '(missing: %s)\n' "$path" >> "$OUT"
  fi
}

{
  printf '# Android reverse evidence bundle\n\n'
  printf '%s\n' "- generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\n' "- session_dir: $SESSION_DIR"
} > "$OUT"

section "Quick scan candidates"
quick_scan_dir="$(find "$SESSION_DIR/decompiled" -path '*/quick_scan' -type d 2>/dev/null | sort | tail -1)"
if [[ -n "$quick_scan_dir" ]]; then
  printf '%s\n\n' "- quick_scan_dir: $quick_scan_dir" >> "$OUT"
  fence_file "$quick_scan_dir/SUMMARY.md" 160
  fence_file "$quick_scan_dir/network_candidates.txt" 160
  fence_file "$quick_scan_dir/business_network_sources.txt" 160
else
  printf '(no quick_scan directory found)\n' >> "$OUT"
fi

section "Network tail"
fence_file "$SESSION_DIR/network.jsonl" 80

section "Frida output files"
find "$SESSION_DIR/frida/output" -maxdepth 1 -type f 2>/dev/null | sort | tail -40 >> "$OUT" || true

section "Latest Frida stdout"
latest_frida_stdout="$(find "$SESSION_DIR/frida/output" -maxdepth 1 -name '*.stdout.log' -type f 2>/dev/null | sort | tail -1)"
if [[ -n "$latest_frida_stdout" ]]; then
  fence_file "$latest_frida_stdout" 160
else
  printf '(no Frida stdout log found)\n' >> "$OUT"
fi

section "Logcat artifacts"
find "$SESSION_DIR/logcat" -maxdepth 2 -type f 2>/dev/null | sort | tail -40 >> "$OUT" || true
fence_file "$SESSION_DIR/logcat.jsonl" 80

section "Package reports"
find "$SESSION_DIR/packages" -maxdepth 3 -type f 2>/dev/null | sort | tail -40 >> "$OUT" || true

section "Reproduction scripts"
find "$SCRIPT_DIR" -maxdepth 1 -type f \( -name 'reproduce_*' -o -name '*.py' -o -name '*.sh' \) | sort >> "$OUT" || true

echo "Evidence bundle: $OUT"
''';

const String _networkSecurityConfigXml =
    '''<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="true">
        <trust-anchors>
            <certificates src="system" />
            <certificates src="user" />
        </trust-anchors>
    </base-config>
    <debug-overrides>
        <trust-anchors>
            <certificates src="user" />
        </trust-anchors>
    </debug-overrides>
</network-security-config>
''';

const String _manifestNetworkConfigSnippet =
    '''<!-- Merge these attributes into the target <application> element. -->
<application
    android:networkSecurityConfig="@xml/network_security_config"
    android:usesCleartextTraffic="true">
</application>
''';

const String _installMitmCaRootScript = r'''#!/usr/bin/env bash
set -euo pipefail

CERT_PATH="${1:-${MITM_CERT_PATH:-$HOME/.mitmproxy/mitmproxy-ca-cert.pem}}"
ADB_SERIAL="${ADB_SERIAL:-}"
ADB=(adb)
if [[ -n "$ADB_SERIAL" ]]; then
  ADB=(adb -s "$ADB_SERIAL")
fi

if [[ ! -f "$CERT_PATH" ]]; then
  echo "mitmproxy CA not found: $CERT_PATH" >&2
  exit 2
fi

HASH="$(openssl x509 -inform PEM -subject_hash_old -in "$CERT_PATH" | head -1)"
TMP_CERT="/tmp/${HASH}.0"
cp "$CERT_PATH" "$TMP_CERT"

"${ADB[@]}" root
"${ADB[@]}" remount
"${ADB[@]}" push "$TMP_CERT" "/system/etc/security/cacerts/${HASH}.0"
"${ADB[@]}" shell "chmod 644 /system/etc/security/cacerts/${HASH}.0"
"${ADB[@]}" shell "ls -l /system/etc/security/cacerts/${HASH}.0"
''';

const String _generateDebugKeystoreScript = r'''#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYSTORE="${1:-$OUT_DIR/openhand-debug.keystore}"
ALIAS="${OPENHAND_KEY_ALIAS:-openhand}"
STOREPASS="${OPENHAND_KEYSTORE_PASS:-android}"
KEYPASS="${OPENHAND_KEY_PASS:-android}"

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found. Install a JDK first." >&2
  exit 2
fi

if [[ -f "$KEYSTORE" ]]; then
  echo "keystore already exists: $KEYSTORE"
  exit 0
fi

keytool -genkeypair \
  -keystore "$KEYSTORE" \
  -storepass "$STOREPASS" \
  -keypass "$KEYPASS" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=OpenHand Android Reverse,O=OpenHand,C=US"

echo "created: $KEYSTORE"
''';

const String _signRepackedApkScript = r'''#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: bash sign_repacked_apk.sh <unsigned.apk> [signed.apk]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNSIGNED_APK="$1"
SIGNED_APK="${2:-${UNSIGNED_APK%.apk}-signed.apk}"
ALIGNED_APK="${SIGNED_APK%.apk}-aligned.apk"
KEYSTORE="${OPENHAND_KEYSTORE:-$SCRIPT_DIR/openhand-debug.keystore}"
ALIAS="${OPENHAND_KEY_ALIAS:-openhand}"
STOREPASS="${OPENHAND_KEYSTORE_PASS:-android}"
KEYPASS="${OPENHAND_KEY_PASS:-android}"

find_android_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  find "$sdk/build-tools" -name "$name" -type f 2>/dev/null | sort -r | head -1
}

APKSIGNER="$(find_android_tool apksigner)"
ZIPALIGN="$(find_android_tool zipalign)"
if [[ -z "$APKSIGNER" || ! -x "$APKSIGNER" ]]; then
  echo "apksigner not found. Install Android SDK build-tools." >&2
  exit 3
fi
if [[ -z "$ZIPALIGN" || ! -x "$ZIPALIGN" ]]; then
  echo "zipalign not found. Install Android SDK build-tools." >&2
  exit 3
fi
if [[ ! -f "$KEYSTORE" ]]; then
  bash "$SCRIPT_DIR/generate_debug_keystore.sh" "$KEYSTORE"
fi
if [[ ! -f "$UNSIGNED_APK" ]]; then
  echo "unsigned APK not found: $UNSIGNED_APK" >&2
  exit 4
fi

"$ZIPALIGN" -f -p 4 "$UNSIGNED_APK" "$ALIGNED_APK"
"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$ALIAS" \
  --ks-pass "pass:$STOREPASS" \
  --key-pass "pass:$KEYPASS" \
  --out "$SIGNED_APK" \
  "$ALIGNED_APK"
"$APKSIGNER" verify --print-certs "$SIGNED_APK"

echo "signed: $SIGNED_APK"
''';

const String _verifyApkSignatureScript = r'''#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: bash verify_apk_signature.sh <apk>" >&2
  exit 2
fi

APK="$1"
if [[ ! -f "$APK" ]]; then
  echo "APK not found: $APK" >&2
  exit 3
fi

APKSIGNER="$(command -v apksigner || true)"
if [[ -z "$APKSIGNER" ]]; then
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  APKSIGNER="$(find "$SDK/build-tools" -name apksigner -type f 2>/dev/null | sort -r | head -1)"
fi
if [[ -z "$APKSIGNER" || ! -x "$APKSIGNER" ]]; then
  echo "apksigner not found. Install Android SDK build-tools." >&2
  exit 4
fi

"$APKSIGNER" verify --verbose --print-certs "$APK"
''';

String _certificateReadme(String? packageName) {
  final target = packageName == null || packageName.isEmpty
      ? '<target package>'
      : packageName;
  return '''# Android reverse certificate artifacts

Target: $target

Files:
- `res/xml/network_security_config.xml`: trusts system and user CAs for debug capture.
- `AndroidManifest.application.xml`: application attribute snippet for apktool merge.
- `install_mitm_ca_root.sh`: pushes mitmproxy CA as a system cert on rooted devices.
- `generate_debug_keystore.sh`: creates a reusable OpenHand debug keystore.
- `sign_repacked_apk.sh`: zipaligns and signs a rebuilt APK.
- `verify_apk_signature.sh`: verifies APK signature schemes and certs.

Flow:
1. For repackaging, copy `res/xml/network_security_config.xml` into apktool output and merge the manifest snippet into `<application>`.
2. For rooted dynamic capture, run `ADB_SERIAL=<serial> bash install_mitm_ca_root.sh`.
3. For rebuilt APKs, run `bash sign_repacked_apk.sh <unsigned.apk> <signed.apk>`.
4. Use the Network tab mitmproxy JSONL addon to write `network.jsonl`.
5. If SSL pinning remains, use `hook_ssl_pinning.js` before capturing traffic.
''';
}
