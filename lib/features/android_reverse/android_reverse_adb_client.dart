import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';

const String _kTag = 'android_reverse_adb_client';
const Duration _kAdbCommandTimeout = Duration(seconds: 30);

class AdbCommandResult {
  const AdbCommandResult({
    required this.args,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });

  final List<String> args;
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  bool get ok => exitCode == 0 && !timedOut;

  bool get hasOutput => stdout.trim().isNotEmpty || stderr.trim().isNotEmpty;

  bool get hasUsableStdout => stdout.trim().isNotEmpty;

  String get commandLine => 'adb ${args.join(' ')}';

  String get combinedOutput {
    final out = stdout.trim();
    final err = stderr.trim();
    if (out.isEmpty && err.isEmpty) return '';
    if (out.isEmpty) return err;
    if (err.isEmpty) return out;
    return '$out\n$err';
  }
}

/// ADB 设备信息。
class AdbDevice {
  const AdbDevice({
    required this.serial,
    required this.state,
    this.model,
    this.product,
    this.transportId,
  });

  final String serial;

  /// online | offline | unauthorized | recovery | ...
  final String state;
  final String? model;
  final String? product;
  final String? transportId;

  bool get isOnline => state == 'device';

  @override
  String toString() => '$serial ($state${model != null ? ', $model' : ''})';
}

/// APP 进程信息（通过 adb shell ps 获取）。
class AndroidProcess {
  const AndroidProcess({
    required this.pid,
    required this.name,
    this.user,
    this.ppid,
  });

  final int pid;
  final String name;
  final String? user;
  final int? ppid;

  @override
  String toString() => '$name (pid=$pid)';
}

/// 精简 ADB 客户端，封装 `adb` 命令行调用。
///
/// 所有操作均通过 `adb` 可执行文件完成；调用方需确保 adb 已在 PATH 中
/// 或通过 [adbPath] 显式指定路径。
class AndroidReverseAdbClient {
  AndroidReverseAdbClient({String? adbPath, this.deviceSerial})
    : adbPath = adbPath ?? 'adb';

  final String adbPath;

  /// 固定设备序列号；null 表示在当前唯一在线设备上执行。
  final String? deviceSerial;

  // ── 设备列表 ─────────────────────────────────────────────────────────

  Future<List<AdbDevice>> listDevices() async {
    final result = await _run(<String>['devices', '-l']);
    if (result == null) return const <AdbDevice>[];
    final lines = const LineSplitter().convert(result);
    final devices = <AdbDevice>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('List of')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final serial = parts[0];
      final state = parts[1];
      String? model;
      String? product;
      String? transportId;
      for (final kv in parts.skip(2)) {
        if (kv.startsWith('model:')) model = kv.substring(6);
        if (kv.startsWith('product:')) product = kv.substring(8);
        if (kv.startsWith('transport_id:')) {
          transportId = kv.substring(13);
        }
      }
      devices.add(
        AdbDevice(
          serial: serial,
          state: state,
          model: model,
          product: product,
          transportId: transportId,
        ),
      );
    }
    return devices;
  }

  Future<AdbDevice?> onlineDevice() async {
    if (deviceSerial != null) {
      final all = await listDevices();
      return all
          .where((d) => d.serial == deviceSerial && d.isOnline)
          .firstOrNull;
    }
    final all = await listDevices();
    final online = all.where((d) => d.isOnline).toList(growable: false);
    return online.length == 1 ? online.first : null;
  }

  // ── 基本 Shell 命令 ───────────────────────────────────────────────────

  Future<String?> shell(String command) async {
    return _runDevice(<String>['shell', command]);
  }

  Future<AdbCommandResult> shellDetailed(String command, {Duration? timeout}) {
    return _runDeviceDetailed(<String>['shell', command], timeout: timeout);
  }

  Future<String?> shellLines(List<String> args) async {
    return _runDevice(<String>['shell', ...args]);
  }

  // ── APP 管理 ──────────────────────────────────────────────────────────

  Future<List<String>> listPackages({bool thirdParty = true}) async {
    final flag = thirdParty ? '-3' : '';
    final raw = await shell('pm list packages $flag'.trim());
    if (raw == null) return const <String>[];
    final packages = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('package:'))
        .map((l) => l.substring(8))
        .where((l) => l.isNotEmpty)
        .toList();
    packages.sort();
    return List<String>.unmodifiable(packages);
  }

  Future<String?> getPackagePath(String packageName) async {
    if (!_looksLikePackageName(packageName)) return null;
    final raw = await shell('pm path $packageName');
    if (raw == null) return null;
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('package:')) return trimmed.substring(8).trim();
    }
    return null;
  }

  Future<String?> getPackageVersion(String packageName) async {
    if (!_looksLikePackageName(packageName)) return null;
    final raw = await shell('dumpsys package $packageName');
    if (raw == null) return null;
    String? versionName;
    String? versionCode;
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('versionName=')) {
        versionName = trimmed.substring(12).trim();
      } else if (trimmed.startsWith('versionCode=')) {
        versionCode = trimmed.substring(12).split(RegExp(r'\s+')).first.trim();
      }
    }
    if (versionName != null && versionName.isNotEmpty) {
      if (versionCode != null && versionCode.isNotEmpty) {
        return '$versionName ($versionCode)';
      }
      return versionName;
    }
    return versionCode;
  }

  Future<String?> resolveLauncherActivity(String packageName) async {
    if (!_looksLikePackageName(packageName)) return null;
    final raw = await shell(
      'cmd package resolve-activity --brief $packageName',
    );
    if (raw == null || raw.trim().isEmpty) return null;
    for (final line
        in raw.split('\n').map((line) => line.trim()).toList().reversed) {
      if (line.isEmpty || !line.contains('/')) continue;
      if (line.toLowerCase().contains('no activity')) continue;
      return line;
    }
    return null;
  }

  Future<Map<String, String>> getProperties() async {
    final raw = await shell('getprop');
    if (raw == null || raw.trim().isEmpty) return const <String, String>{};
    final props = <String, String>{};
    final pattern = RegExp(r'^\[([^\]]+)\]: \[(.*)\]$');
    for (final line in raw.split('\n')) {
      final match = pattern.firstMatch(line.trim());
      if (match == null) continue;
      props[match.group(1)!] = match.group(2) ?? '';
    }
    return props;
  }

  Future<bool> installApk(String localApkPath) async {
    final result = await _runDevice(<String>[
      'install',
      '-r',
      localApkPath,
    ], timeout: const Duration(minutes: 3));
    return result != null && result.contains('Success');
  }

  Future<bool> forceStopApp(String packageName) async {
    final result = await shell('am force-stop $packageName');
    return result != null;
  }

  Future<AdbCommandResult> forceStopAppDetailed(String packageName) {
    if (!_looksLikePackageName(packageName)) {
      return Future<AdbCommandResult>.value(
        AdbCommandResult(
          args: const <String>['shell', 'am force-stop <invalid-package>'],
          exitCode: -1,
          stdout: '',
          stderr: 'Invalid Android package name: $packageName',
        ),
      );
    }
    return shellDetailed('am force-stop $packageName');
  }

  Future<bool> startActivity(String packageName, {String? activity}) async {
    final String cmd;
    if (activity != null) {
      cmd = 'am start -n $packageName/$activity';
    } else {
      cmd = 'monkey -p $packageName -c android.intent.category.LAUNCHER 1';
    }
    final result = await shell(cmd);
    return result != null;
  }

  Future<AdbCommandResult> startPackageDetailed(String packageName) async {
    if (!_looksLikePackageName(packageName)) {
      return AdbCommandResult(
        args: const <String>['shell', 'monkey -p <invalid-package>'],
        exitCode: -1,
        stdout: '',
        stderr: 'Invalid Android package name: $packageName',
      );
    }
    final launcher = await resolveLauncherActivity(packageName);
    if (launcher != null && launcher.isNotEmpty) {
      final result = await shellDetailed(
        'am start -W -n $launcher',
        timeout: const Duration(seconds: 12),
      );
      final output = result.combinedOutput.toLowerCase();
      if (!output.contains('error type 3') &&
          !output.contains('does not exist')) {
        return result;
      }
    }
    return shellDetailed(
      'monkey -p $packageName -c android.intent.category.LAUNCHER 1',
      timeout: const Duration(seconds: 12),
    );
  }

  // ── 进程管理 ──────────────────────────────────────────────────────────

  Future<List<AndroidProcess>> listProcesses({String? filterName}) async {
    final raw = await shell('ps -A');
    if (raw == null) return const <AndroidProcess>[];
    final processes = <AndroidProcess>[];
    final lines = raw.split('\n');
    for (final line in lines.skip(1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 9) continue;
      final pid = int.tryParse(parts[1]);
      if (pid == null) continue;
      final name = parts.last;
      if (filterName != null &&
          !name.toLowerCase().contains(filterName.toLowerCase())) {
        continue;
      }
      processes.add(
        AndroidProcess(
          pid: pid,
          name: name,
          user: parts[0],
          ppid: int.tryParse(parts[2]),
        ),
      );
    }
    return processes;
  }

  // ── 文件传输 ──────────────────────────────────────────────────────────

  Future<bool> push(String localPath, String remotePath) async {
    final result = await _runDevice(<String>[
      'push',
      localPath,
      remotePath,
    ], timeout: const Duration(minutes: 5));
    return result != null && !result.toLowerCase().contains('error');
  }

  Future<bool> pull(String remotePath, String localPath) async {
    final result = await _runDevice(<String>[
      'pull',
      remotePath,
      localPath,
    ], timeout: const Duration(minutes: 5));
    return result != null && !result.toLowerCase().contains('error');
  }

  // ── Logcat ────────────────────────────────────────────────────────────

  /// 拉取最近 [lines] 行 logcat（非流式）。
  Future<String?> logcat({String? tag, String? level, int lines = 200}) async {
    final result = await logcatDetailed(tag: tag, level: level, lines: lines);
    if (result.timedOut && !result.hasUsableStdout) return null;
    if (!result.ok && !result.hasUsableStdout) return null;
    return result.stdout.trim();
  }

  Future<AdbCommandResult> logcatDetailed({
    String? tag,
    String? level,
    int lines = 200,
  }) {
    final filter = <String>[];
    if (tag != null && tag.trim().isNotEmpty) {
      filter
        ..add('${tag.trim()}:${level ?? 'V'}')
        ..add('*:S');
    }
    return _runDeviceDetailed(<String>[
      'logcat',
      '-d',
      '-t',
      '$lines',
      if (filter.isNotEmpty) ...filter,
    ], timeout: const Duration(seconds: 15));
  }

  // ── 端口转发 ──────────────────────────────────────────────────────────

  Future<bool> forwardPort(int localPort, int remotePort) async {
    final result = await _runDevice(<String>[
      'forward',
      'tcp:$localPort',
      'tcp:$remotePort',
    ]);
    return result != null;
  }

  Future<bool> removeForward(int localPort) async {
    final result = await _runDevice(<String>[
      'forward',
      '--remove',
      'tcp:$localPort',
    ]);
    return result != null;
  }

  Future<String?> listForwards() {
    return _runDevice(<String>['forward', '--list']);
  }

  Future<bool> removeAllForwards() async {
    final result = await _runDevice(<String>['forward', '--remove-all']);
    return result != null;
  }

  Future<AdbCommandResult> forwardPortDetailed(int localPort, int remotePort) {
    return _runDeviceDetailed(<String>[
      'forward',
      'tcp:$localPort',
      'tcp:$remotePort',
    ]);
  }

  Future<AdbCommandResult> removeForwardDetailed(int localPort) {
    return _runDeviceDetailed(<String>[
      'forward',
      '--remove',
      'tcp:$localPort',
    ]);
  }

  Future<AdbCommandResult> connect(String endpoint) {
    return _runDetailed(<String>['connect', endpoint]);
  }

  Future<AdbCommandResult> disconnect([String? endpoint]) {
    return _runDetailed(<String>[
      'disconnect',
      if (endpoint != null && endpoint.trim().isNotEmpty) endpoint.trim(),
    ]);
  }

  Future<AdbCommandResult> reboot([String? mode]) {
    return _runDeviceDetailed(<String>[
      'reboot',
      if (mode != null && mode.trim().isNotEmpty) mode.trim(),
    ]);
  }

  Future<AdbCommandResult> root() => _runDeviceDetailed(<String>['root']);

  Future<AdbCommandResult> remount() => _runDeviceDetailed(<String>['remount']);

  // ── 内部实现 ──────────────────────────────────────────────────────────

  List<String> _deviceArgs() {
    if (deviceSerial != null) return <String>['-s', deviceSerial!];
    return const <String>[];
  }

  Future<String?> _run(List<String> args, {Duration? timeout}) async {
    final result = await _runDetailed(args, timeout: timeout);
    if (result.timedOut && !result.hasUsableStdout) return null;
    if (!result.ok && !result.hasUsableStdout) {
      final stderr = result.stderr.trim();
      silentLog(
        _kTag,
        'adb ${args.join(' ')} exited ${result.exitCode}${stderr.isNotEmpty ? ": $stderr" : ""}',
        'exitCode=${result.exitCode}',
      );
    }
    return result.stdout.trim();
  }

  Future<AdbCommandResult> _runDetailed(
    List<String> args, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _kAdbCommandTimeout;
    Process? process;
    try {
      process = await startTrackedProcess(adbPath, args);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      var timedOut = false;
      late int exitCode;
      try {
        exitCode = await process.exitCode.timeout(effectiveTimeout);
      } on TimeoutException {
        timedOut = true;
        exitCode = -1;
        process.kill();
        await Future<void>.delayed(const Duration(milliseconds: 180));
        process.kill(ProcessSignal.sigkill);
      }
      final stdout = await stdoutFuture.timeout(
        const Duration(milliseconds: 350),
        onTimeout: () => '',
      );
      var stderr = await stderrFuture.timeout(
        const Duration(milliseconds: 350),
        onTimeout: () => '',
      );
      if (timedOut && stderr.trim().isEmpty) {
        stderr = 'ADB command timed out before completion.';
      }
      return AdbCommandResult(
        args: List<String>.unmodifiable(args),
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        timedOut: timedOut,
      );
    } catch (e, st) {
      process?.kill(ProcessSignal.sigkill);
      silentLog(_kTag, 'adb ${args.join(' ')} failed', e, st);
      return AdbCommandResult(
        args: List<String>.unmodifiable(args),
        exitCode: -1,
        stdout: '',
        stderr: '$e',
      );
    }
  }

  Future<String?> _runDevice(List<String> args, {Duration? timeout}) {
    return _run(<String>[..._deviceArgs(), ...args], timeout: timeout);
  }

  Future<AdbCommandResult> _runDeviceDetailed(
    List<String> args, {
    Duration? timeout,
  }) {
    return _runDetailed(<String>[..._deviceArgs(), ...args], timeout: timeout);
  }

  bool _looksLikePackageName(String value) {
    final packageName = value.trim();
    if (packageName.length > 220) return false;
    return RegExp(
      r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
    ).hasMatch(packageName);
  }
}
