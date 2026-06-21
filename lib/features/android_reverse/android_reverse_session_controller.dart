import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import 'android_reverse_adb_client.dart';
import 'android_reverse_session_config.dart';

const String _kTag = 'android_reverse_session_controller';
const Duration _kDeviceWatchdogInterval = Duration(seconds: 8);
const Duration _kDeviceReportTimeout = Duration(seconds: 18);
const Duration _kPackageReportTimeout = Duration(seconds: 12);
const Duration _kStaticQuickScanTimeout = Duration(seconds: 35);
const Duration _kStaticQuickScanTimeoutSkew = Duration(milliseconds: 500);
const Duration _kArtifactChmodTimeout = Duration(seconds: 2);
const int _kPackageReportSummaryMaxLines = 220;
const int _kStaticQuickScanPreviewLines = 80;
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
  'logs',
];

/// Android 逆向会话状态。
enum AndroidReverseSessionState { idle, running, deviceLost, stopped }

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
  }) : _adbClient = AndroidReverseAdbClient(
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
  String get decompiledDir => '$artifactsRootDir/decompiled';
  String get mcpDir => '$artifactsRootDir/mcp';
  String get mcpTemplatesPath =>
      '$mcpDir/openhand_android_reverse_mcp_templates.json';
  String get mcpReadmePath => '$mcpDir/README.md';
  String get logcatDir => '$artifactsRootDir/logcat';
  String get networkDir => '$artifactsRootDir/network';
  String get mitmproxyAddonPath => '$networkDir/openhand_mitm_jsonl.py';
  String get certsDir => '$artifactsRootDir/certs';
  String get scriptsDir => '$artifactsRootDir/scripts';
  String get adbOneShotScriptPath => '$scriptsDir/adb_one_shot.sh';
  String get dynamicProbeScriptPath => '$scriptsDir/android_dynamic_probe.sh';
  String get logsDir => '$artifactsRootDir/logs';

  final AndroidReverseAdbClient _adbClient;
  AndroidReverseAdbClient get adbClient => _adbClient;

  AndroidReverseSessionState _state = AndroidReverseSessionState.idle;
  AndroidReverseSessionState get state => _state;

  AdbDevice? _connectedDevice;
  AdbDevice? get connectedDevice => _connectedDevice;

  List<AdbDevice> _allDevices = const <AdbDevice>[];
  List<AdbDevice> get allDevices => _allDevices;

  List<AndroidProcess> _processes = const <AndroidProcess>[];
  List<AndroidProcess> get processes => _processes;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _disposed = false;
  Timer? _watchdogTimer;

  bool get isRunning => _state == AndroidReverseSessionState.running;

  void clearErrorMessage() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _safeNotify();
  }

  Future<void> start() async {
    if (_state != AndroidReverseSessionState.idle) return;
    await _ensureArtifactDirectories();
    await _writeMcpLinkageArtifacts(updateError: false);
    if (_state == AndroidReverseSessionState.stopped || _disposed) return;
    await _refreshDevices();
    if (_state == AndroidReverseSessionState.stopped || _disposed) return;
    _state = AndroidReverseSessionState.running;
    _watchdogTimer = Timer.periodic(_kDeviceWatchdogInterval, (_) {
      if (!_disposed) _scheduleRefresh();
    });
    _safeNotify();
  }

  Future<void> stop() async {
    if (_state == AndroidReverseSessionState.stopped) return;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _state = AndroidReverseSessionState.stopped;
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
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
    try {
      final procs = await _clientForSerial(
        serial,
      ).listProcesses(filterName: filterName);
      _processes = procs;
      _safeNotify();
      return procs;
    } catch (e, st) {
      silentLog(_kTag, 'refreshProcesses failed', e, st);
      return _processes;
    }
  }

  AndroidReverseAdbClient _clientForSerial(String? serial) {
    final normalizedSerial = serial?.trim();
    if (normalizedSerial == null ||
        normalizedSerial.isEmpty ||
        normalizedSerial == config.deviceSerial) {
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
    if (!_looksLikePackageName(normalizedPackage)) {
      return AdbCommandResult(
        args: const <String>['package-report', '<invalid-package>'],
        exitCode: -1,
        stdout: '',
        stderr: 'Invalid Android package name: $packageName',
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
      await targetDir.create(recursive: true);
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
        File(markdownPath).writeAsString(markdown),
        File(
          jsonPath,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(json)),
      ]);
      return AdbCommandResult(
        args: <String>['package-report', normalizedPackage],
        exitCode: dumpsys.exitCode,
        stdout: <String>[
          'Package report: $markdownPath',
          'Package report JSON: $jsonPath',
          if (paths.isNotEmpty) 'APK paths: ${paths.join(', ')}',
          if (launcher != null && launcher.isNotEmpty) 'Launcher: $launcher',
        ].join('\n'),
        stderr: dumpsys.stderr,
        timedOut: dumpsys.timedOut,
      );
    } catch (e, st) {
      silentLog(_kTag, 'capturePackageReportToArtifacts failed', e, st);
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
      await Directory(logcatDir).create(recursive: true);
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
        File(txtPath).writeAsString(text.isEmpty ? '(empty)\n' : '$text\n'),
        File(
          jsonPath,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(json)),
      ]);
      return AdbCommandResult(
        args: <String>['logcat-snapshot'],
        exitCode: result.exitCode,
        stdout: <String>[
          'Logcat snapshot: $txtPath',
          'Logcat snapshot JSON: $jsonPath',
          if (text.isNotEmpty) 'Captured lines: ${text.split('\n').length}',
        ].join('\n'),
        stderr: result.stderr,
        timedOut: result.timedOut,
      );
    } catch (e, st) {
      silentLog(_kTag, 'captureLogcatSnapshotToArtifacts failed', e, st);
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
        stderr: 'Frida script is empty.',
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
      await Directory(fridaScriptsDir).create(recursive: true);
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
        File(scriptPath).writeAsString('$normalizedScript\n'),
        File(
          jsonPath,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(metadata)),
      ]);
      return AdbCommandResult(
        args: const <String>['frida-script-save'],
        exitCode: 0,
        stdout: <String>[
          'Frida script: $scriptPath',
          'Frida script metadata: $jsonPath',
        ].join('\n'),
        stderr: '',
      );
    } catch (e, st) {
      silentLog(_kTag, 'saveFridaScriptToArtifacts failed', e, st);
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
    final remotePath = '/sdcard/OpenHand/screenshots/$stamp.png';
    final localPath = '$screenshotsDir/$stamp.png';
    await Directory(screenshotsDir).create(recursive: true);
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
    final remotePath = '/sdcard/OpenHand/recordings/$stamp.mp4';
    final localPath = '$recordingsDir/$stamp.mp4';
    await Directory(recordingsDir).create(recursive: true);
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
      await targetDir.create(recursive: true);
      final devices = await _adbClient.listDevices();
      final propsFuture = client.getProperties();
      final forwardsFuture = client.listForwards();
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
        'forwards': (forwards ?? '')
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false),
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
        packageName: packageName,
        launcher: launcher,
        snapshot: snapshot,
        logcat: logcat,
        jsonPath: jsonPath,
      );
      await Future.wait(<Future<void>>[
        File(markdownPath).writeAsString(markdown),
        File(
          jsonPath,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(json)),
      ]);
      return AdbCommandResult(
        args: <String>['device-report', reportSerial],
        exitCode: 0,
        stdout: <String>[
          'Device report: $markdownPath',
          'Device report JSON: $jsonPath',
          if (launcher != null && launcher.isNotEmpty) 'Launcher: $launcher',
        ].join('\n'),
        stderr: <String>[
          if (snapshot.stderr.trim().isNotEmpty) snapshot.stderr.trim(),
          if (logcat.stderr.trim().isNotEmpty) logcat.stderr.trim(),
        ].join('\n'),
        timedOut: snapshot.timedOut || logcat.timedOut,
      );
    } catch (e, st) {
      silentLog(_kTag, 'captureDeviceReportToArtifacts failed', e, st);
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
        stderr: 'No APK path was found for $packageName.',
      );
    }
    final targetDir = Directory('$apksDir/${_safeArtifactName(packageName)}');
    await targetDir.create(recursive: true);
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
  }) async {
    if (Platform.isWindows || !File('/bin/sh').existsSync()) {
      return const AdbCommandResult(
        args: <String>['static-quick-scan'],
        exitCode: -1,
        stdout: '',
        stderr: 'Static quick scan requires /bin/sh.',
      );
    }
    final rawApkPath = (apkPath ?? config.apkPath ?? '').trim();
    if (rawApkPath.isEmpty) {
      return const AdbCommandResult(
        args: <String>['static-quick-scan', '<missing-apk>'],
        exitCode: -1,
        stdout: '',
        stderr: 'APK path is required for static quick scan.',
      );
    }
    final apkFile = File(rawApkPath);
    if (!await apkFile.exists()) {
      return AdbCommandResult(
        args: <String>['static-quick-scan', rawApkPath],
        exitCode: -1,
        stdout: '',
        stderr: 'APK file does not exist: $rawApkPath',
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
    await outputDir.create(recursive: true);
    final sw = Stopwatch()..start();
    final result = await runTrackedProcessOrFailed(
      '/bin/sh',
      <String>['-lc', _staticQuickScanScript],
      timeout: _kStaticQuickScanTimeout,
      tag: 'android_reverse.static_quick_scan',
      environment: <String, String>{
        'APK_PATH': rawApkPath,
        'OUT_DIR': outputDir.path,
      },
    );
    sw.stop();
    final timedOut =
        result.exitCode == -1 &&
        sw.elapsed + _kStaticQuickScanTimeoutSkew >= _kStaticQuickScanTimeout;
    final summary = await _staticQuickScanSummary(
      outputDir,
      result,
      timedOut: timedOut,
    );
    return AdbCommandResult(
      args: <String>['static-quick-scan', rawApkPath],
      exitCode: result.exitCode,
      stdout: summary,
      stderr: result.stderr.toString(),
      timedOut: timedOut,
    );
  }

  Future<int> appendLogcatLines(
    Iterable<String> lines, {
    String? tag,
    String? level,
    String? packageName,
    String? pid,
    String? serial,
  }) async {
    final normalized = lines
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) return 0;
    try {
      await Directory(logsDir).create(recursive: true);
      final sink = File(logcatJsonlPath).openWrite(mode: FileMode.append);
      final capturedAt = DateTime.now().toUtc().toIso8601String();
      for (final line in normalized) {
        sink.writeln(
          jsonEncode(<String, Object?>{
            'captured_at': capturedAt,
            'line': line,
            if (tag != null && tag.trim().isNotEmpty) 'tag': tag.trim(),
            if (level != null && level.trim().isNotEmpty)
              'level_filter': level.trim().toUpperCase(),
            if (packageName != null && packageName.trim().isNotEmpty)
              'package_name': packageName.trim(),
            if (pid != null && pid.trim().isNotEmpty) 'pid': pid.trim(),
            if (serial != null && serial.trim().isNotEmpty)
              'device_serial': serial.trim(),
          }),
        );
      }
      await sink.flush();
      await sink.close();
      return normalized.length;
    } catch (e, st) {
      silentLog(_kTag, 'appendLogcatLines failed', e, st);
      _errorMessage = '$e';
      _safeNotify();
      return 0;
    }
  }

  Future<String> ensureMitmproxyJsonlAddon() async {
    try {
      await Directory(networkDir).create(recursive: true);
      await File(networkJsonlPath).create(recursive: true);
      final file = File(mitmproxyAddonPath);
      await file.writeAsString(_mitmproxyJsonlAddon);
      return file.path;
    } catch (e, st) {
      silentLog(_kTag, 'ensureMitmproxyJsonlAddon failed', e, st);
      _errorMessage = '$e';
      _safeNotify();
      rethrow;
    }
  }

  Future<String> ensureCertificateArtifacts({String? packageName}) async {
    try {
      final resXmlDir = Directory('$certsDir/res/xml');
      await resXmlDir.create(recursive: true);
      final networkSecurityConfigPath =
          '${resXmlDir.path}/network_security_config.xml';
      final manifestSnippetPath = '$certsDir/AndroidManifest.application.xml';
      final installScriptPath = '$certsDir/install_mitm_ca_root.sh';
      final generateKeystorePath = '$certsDir/generate_debug_keystore.sh';
      final signApkPath = '$certsDir/sign_repacked_apk.sh';
      final verifySignaturePath = '$certsDir/verify_apk_signature.sh';
      final readmePath = '$certsDir/README.md';
      final pkg = packageName?.trim();
      await Future.wait(<Future<File>>[
        File(
          networkSecurityConfigPath,
        ).writeAsString(_networkSecurityConfigXml),
        File(manifestSnippetPath).writeAsString(_manifestNetworkConfigSnippet),
        File(installScriptPath).writeAsString(_installMitmCaRootScript),
        File(generateKeystorePath).writeAsString(_generateDebugKeystoreScript),
        File(signApkPath).writeAsString(_signRepackedApkScript),
        File(verifySignaturePath).writeAsString(_verifyApkSignatureScript),
        File(readmePath).writeAsString(_certificateReadme(pkg)),
      ]);
      return <String>[
        'Certificate artifacts: $certsDir',
        'network_security_config: $networkSecurityConfigPath',
        'manifest_snippet: $manifestSnippetPath',
        'root_ca_install_script: $installScriptPath',
        'generate_debug_keystore: $generateKeystorePath',
        'sign_repacked_apk: $signApkPath',
        'verify_apk_signature: $verifySignaturePath',
        'readme: $readmePath',
      ].join('\n');
    } catch (e, st) {
      silentLog(_kTag, 'ensureCertificateArtifacts failed', e, st);
      _errorMessage = '$e';
      _safeNotify();
      rethrow;
    }
  }

  Future<String> ensureMcpLinkageArtifacts() async {
    try {
      return await _writeMcpLinkageArtifacts(updateError: true);
    } catch (e, st) {
      silentLog(_kTag, 'ensureMcpLinkageArtifacts failed', e, st);
      _errorMessage = '$e';
      _safeNotify();
      rethrow;
    }
  }

  // ── 内部 ───────────────────────────────────────────────────────────────

  Future<String> _writeMcpLinkageArtifacts({required bool updateError}) async {
    try {
      await Future.wait(<Future<void>>[
        Directory(mcpDir).create(recursive: true),
        Directory(fridaScriptsDir).create(recursive: true),
        Directory(fridaOutputDir).create(recursive: true),
        Directory(scriptsDir).create(recursive: true),
      ]);
      final generatedAt = DateTime.now().toUtc().toIso8601String();
      await Future.wait(<Future<File>>[
        File(
          mcpTemplatesPath,
        ).writeAsString(_mcpLinkageTemplatesJson(generatedAt)),
        File(mcpReadmePath).writeAsString(_mcpLinkageReadme),
        File(fridaReadmePath).writeAsString(_fridaRunbookReadme),
        File(adbOneShotScriptPath).writeAsString(_adbOneShotScript),
        File(dynamicProbeScriptPath).writeAsString(_androidDynamicProbeScript),
      ]);
      if (!Platform.isWindows) {
        final chmod = File('/bin/chmod').existsSync() ? '/bin/chmod' : 'chmod';
        await runTrackedProcessOrFailed(
          chmod,
          <String>['+x', adbOneShotScriptPath, dynamicProbeScriptPath],
          timeout: _kArtifactChmodTimeout,
          tag: 'android_reverse.mcp_linkage_chmod',
        );
      }
      return <String>[
        'MCP linkage artifacts: $mcpDir',
        'templates_json: $mcpTemplatesPath',
        'readme: $mcpReadmePath',
        'adb_one_shot: $adbOneShotScriptPath',
        'dynamic_probe: $dynamicProbeScriptPath',
        'frida_readme: $fridaReadmePath',
      ].join('\n');
    } catch (e, st) {
      silentLog(_kTag, 'write MCP linkage artifacts failed', e, st);
      if (updateError) {
        _errorMessage = '$e';
        _safeNotify();
        rethrow;
      }
      return 'Failed to write MCP linkage artifacts: $e';
    }
  }

  Future<void> _ensureArtifactDirectories() async {
    try {
      await Directory(artifactsRootDir).create(recursive: true);
      await Future.wait(
        _kAndroidReverseArtifactSubdirs.map(
          (name) =>
              Directory('$artifactsRootDir/$name').create(recursive: true),
        ),
      );
      await Future.wait(<Future<File>>[
        File(logcatJsonlPath).create(recursive: true),
        File(networkJsonlPath).create(recursive: true),
      ]);
    } catch (e, st) {
      silentLog(_kTag, 'ensure artifact directories', e, st);
      _errorMessage = '$e';
    }
  }

  void _scheduleRefresh() {
    unawaited(
      _refreshDevices().catchError((Object e, StackTrace st) {
        silentLog(_kTag, '_scheduleRefresh', e, st);
      }),
    );
  }

  Future<void> _refreshDevices() async {
    try {
      final devices = await _adbClient.listDevices();
      _allDevices = devices;
      _connectedDevice = await _adbClient.onlineDevice();
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
      silentLog(_kTag, '_refreshDevices failed', e, st);
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
        ..writeln('exit: ${result.exitCode}');
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

  String _artifactTimestamp() {
    return DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
  }

  String _safeArtifactName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
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

  bool _looksLikePackageName(String value) {
    final packageName = value.trim();
    if (packageName.length > 220) return false;
    return RegExp(
      r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
    ).hasMatch(packageName);
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
      return raw
          .split('\n')
          .map((line) => line.trimRight())
          .where((line) => line.trim().isNotEmpty)
          .take(_kPackageReportSummaryMaxLines)
          .join('\n');
    }
    return summary.join('\n');
  }

  Future<String> _staticQuickScanSummary(
    Directory outputDir,
    ProcessResult result, {
    required bool timedOut,
  }) async {
    final buffer = StringBuffer()
      ..writeln('Static quick scan output: ${outputDir.path}')
      ..writeln('exit: ${result.exitCode}');
    if (timedOut) {
      buffer.writeln(
        'status: timed out; partial artifacts may still be useful',
      );
    }
    final files = <String>[
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
    for (final name in files) {
      final file = File('${outputDir.path}/$name');
      if (!await file.exists()) continue;
      final lines = await file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .take(_kStaticQuickScanPreviewLines)
          .toList();
      buffer
        ..writeln()
        ..writeln('## $name');
      if (lines.isEmpty) {
        buffer.writeln('(empty)');
      } else {
        buffer.write(lines.join('\n'));
        buffer.writeln();
      }
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
        'adb_one_shot': adbOneShotScriptPath,
        'dynamic_probe': dynamicProbeScriptPath,
        'frida_readme': fridaReadmePath,
        'quick_scan_root': decompiledDir,
        'logcat_jsonl': logcatJsonlPath,
        'network_jsonl': networkJsonlPath,
        'frida_scripts_dir': fridaScriptsDir,
        'frida_output_dir': fridaOutputDir,
      },
      'tool_search_queries': const <String>[
        'select:adb,android,frida,ida,apktool,jadx,anything-analyzer,flutter',
        'select:logcat,device,shell,package,activity,frida',
      ],
      'rules': const <String>[
        'Use only real mcp__* names from Tool Catalog or ToolSearch results.',
        'If an enabled ADB/Frida MCP is missing, report the missing server and fall back to Bash only after device/tool confirmation.',
        'For flaky wireless ADB, use scripts/adb_one_shot.sh with a short timeout and accept usable stdout from timed-out commands.',
        'Do not run adb kill-server, adb start-server, or pkill adb without explicit user approval; prefer single-device short-timeout probes.',
        'Do not guess .MainActivity; resolve launcher activity or use dashboard package launch.',
        'Stop after two repeated failures of the same command, install step, hook, or launch path.',
      ],
      'server_templates': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'android-adb-stdio',
          'purpose': 'ADB shell, package, file transfer, logcat, forward',
          'config': <String, Object?>{
            'mcpServers': <String, Object?>{
              'android-adb': <String, Object?>{
                'enabled': true,
                'probeEnabled': true,
                'type': 'stdio',
                'transport': 'stdio',
                'command': 'npx',
                'args': const <String>['-y', '<adb-mcp-package>'],
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
                'command': 'npx',
                'args': const <String>['-y', '<frida-mcp-package>'],
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
                'command': 'npx',
                'args': const <String>['-y', '<anything-analyzer-package>'],
              },
            },
          },
        },
      ],
      'adb_one_shot_examples': <String>[
        '$adbOneShotScriptPath devices',
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
        'Confirm device with adb devices or ADB MCP.',
        'Run scripts/android_dynamic_probe.sh once before dynamic validation on a flaky device.',
        'Read quick_scan artifacts before dynamic work when APK path exists.',
        'Use MCP for ADB/Frida only when exact mcp__* tools are visible.',
        'Use dashboard-generated cert/network/frida artifacts instead of rewriting boilerplate.',
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}

const String _mcpLinkageReadme = r'''# Android reverse MCP linkage

This directory is generated by the OpenHand Android Reverse dashboard.

Use it as the thread-local source of truth for MCP setup, ToolSearch queries,
and Bash fallback discipline.

Files:
- openhand_android_reverse_mcp_templates.json: MCP templates, checklist, and examples.
- ../scripts/adb_one_shot.sh: short-timeout ADB wrapper for flaky wireless devices.
- ../scripts/android_dynamic_probe.sh: one-pass ADB / launcher / Frida preflight.
- ../frida/README.md: Frida script, server, and output capture runbook.

Rules:
1. Use only real mcp__* tool names from the Tool Catalog or ToolSearch result.
2. If ADB/Frida MCP is enabled but absent, report the missing server before Bash fallback.
3. Prefer quick_scan artifacts for URL/domain evidence before Frida or mitmproxy.
4. Do not guess launcher activities. Resolve them with package manager data.
5. Do not restart the global ADB server (`adb kill-server`, `adb start-server`, `pkill adb`) without explicit user approval.
6. Stop after two repeated failures on the same command, hook, install, or launch path.
''';

const String _fridaRunbookReadme = r'''# Android reverse Frida runbook

Use this directory for Frida scripts, metadata, and captured output.

Directories:
- scripts/: saved hook scripts and metadata generated by the dashboard.
- output/: stdout/stderr captured from frida, frida-ps, and frida-server checks.

Preflight:
1. Run ../scripts/android_dynamic_probe.sh before dynamic validation.
2. Match frida-server to the local `frida --version` and device ABI.
3. Use launcher data from package reports or dynamic_probe; do not guess `.MainActivity`.
4. If Frida CLI or frida-server is missing, report the gap and ask before installing.

Stop rules:
- Do not repeat the same install, launch, attach, or shell command more than twice.
- If ADB times out but stdout has the needed value, treat it as partial success.
- If static quick_scan already proves a domain or URL, Frida is optional validation.
''';

const String _adbOneShotScript = r'''#!/usr/bin/env bash
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

run_with_timeout() {
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$TIMEOUT_SECONDS" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_SECONDS" "$@"
  else
    perl -e '$SIG{ALRM}=sub{exit 124}; alarm shift; exec @ARGV' "$TIMEOUT_SECONDS" "$@"
  fi
}

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
  forward|install|uninstall|push|pull|logcat)
    run_adb "$@"
    status=$?
    ;;
  shell)
    shift
    if [[ $# -eq 0 ]]; then
      echo "missing shell command" >&2
      exit 64
    fi
    run_adb shell "$*" </dev/null
    status=$?
    ;;
  *)
    run_adb shell "$*" </dev/null
    status=$?
    ;;
esac

if [[ "$status" -eq 124 ]]; then
  echo "ADB command timed out after ${TIMEOUT_SECONDS}s" >&2
fi
exit "$status"
''';

const String _androidDynamicProbeScript = r'''#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADB_ONE_SHOT="${ADB_ONE_SHOT:-$SCRIPT_DIR/adb_one_shot.sh}"
ADB_BIN="${ADB_BIN:-adb}"
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

run_with_timeout() {
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$TIMEOUT_SECONDS" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_SECONDS" "$@"
  else
    perl -e '$SIG{ALRM}=sub{exit 124}; alarm shift; exec @ARGV' "$TIMEOUT_SECONDS" "$@"
  fi
}

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

printf 'quick scan completed\n'
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

const String _networkSecurityConfigXml =
    r'''<?xml version="1.0" encoding="utf-8"?>
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
    r'''<!-- Merge these attributes into the target <application> element. -->
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
