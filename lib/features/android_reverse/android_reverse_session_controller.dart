import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app/support/silent_log.dart';
import 'android_reverse_adb_client.dart';
import 'android_reverse_session_config.dart';

const String _kTag = 'android_reverse_session_controller';
const Duration _kDeviceWatchdogInterval = Duration(seconds: 8);
const List<String> _kAndroidReverseArtifactSubdirs = <String>[
  'apks',
  'screenshots',
  'recordings',
  'frida',
  'decompiled',
  'network',
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
  String get apksDir => '$artifactsRootDir/apks';
  String get screenshotsDir => '$artifactsRootDir/screenshots';
  String get recordingsDir => '$artifactsRootDir/recordings';
  String get fridaDir => '$artifactsRootDir/frida';
  String get decompiledDir => '$artifactsRootDir/decompiled';
  String get networkDir => '$artifactsRootDir/network';
  String get scriptsDir => '$artifactsRootDir/scripts';
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

  // ── 内部 ───────────────────────────────────────────────────────────────

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
}
