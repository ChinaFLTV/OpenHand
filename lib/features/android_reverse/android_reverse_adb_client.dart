import 'dart:async';
import 'dart:convert';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';

const String _kTag = 'android_reverse_adb_client';
const Duration _kAdbCommandTimeout = Duration(seconds: 30);

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
  AndroidReverseAdbClient({String? adbPath, String? deviceSerial})
    : adbPath = adbPath ?? 'adb',
      deviceSerial = deviceSerial;

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
      return all.where((d) => d.serial == deviceSerial && d.isOnline).firstOrNull;
    }
    final all = await listDevices();
    final online = all.where((d) => d.isOnline).toList(growable: false);
    return online.length == 1 ? online.first : null;
  }

  // ── 基本 Shell 命令 ───────────────────────────────────────────────────

  Future<String?> shell(String command) async {
    return _runDevice(<String>['shell', command]);
  }

  Future<String?> shellLines(List<String> args) async {
    return _runDevice(<String>['shell', ...args]);
  }

  // ── APP 管理 ──────────────────────────────────────────────────────────

  Future<List<String>> listPackages({bool thirdParty = true}) async {
    final flag = thirdParty ? '-3' : '';
    final raw = await shell('pm list packages $flag'.trim());
    if (raw == null) return const <String>[];
    return raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('package:'))
        .map((l) => l.substring(8))
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
  }

  Future<String?> getPackagePath(String packageName) async {
    final raw = await shell('pm path $packageName');
    if (raw == null) return null;
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('package:')) return trimmed.substring(8).trim();
    }
    return null;
  }

  Future<String?> getPackageVersion(String packageName) async {
    final raw = await shell(
      'dumpsys package $packageName | grep versionName',
    );
    if (raw == null) return null;
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('versionName=')) {
        return trimmed.substring(12).trim();
      }
    }
    return null;
  }

  Future<bool> installApk(String localApkPath) async {
    final result = await _runDevice(
      <String>['install', '-r', localApkPath],
      timeout: const Duration(minutes: 3),
    );
    return result != null && result.contains('Success');
  }

  Future<bool> forceStopApp(String packageName) async {
    final result = await shell('am force-stop $packageName');
    return result != null;
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
    final result = await _runDevice(
      <String>['push', localPath, remotePath],
      timeout: const Duration(minutes: 5),
    );
    return result != null && !result.toLowerCase().contains('error');
  }

  Future<bool> pull(String remotePath, String localPath) async {
    final result = await _runDevice(
      <String>['pull', remotePath, localPath],
      timeout: const Duration(minutes: 5),
    );
    return result != null && !result.toLowerCase().contains('error');
  }

  // ── Logcat ────────────────────────────────────────────────────────────

  /// 拉取最近 [lines] 行 logcat（非流式）。
  Future<String?> logcat({
    String? tag,
    String? level,
    int lines = 200,
  }) async {
    final filter = <String>[];
    if (tag != null) filter.add('$tag:${level ?? 'V'}');
    filter.add('*:S');
    return _runDevice(
      <String>[
        'logcat',
        '-d',
        '-t',
        '$lines',
        if (filter.isNotEmpty) ...filter,
      ],
      timeout: const Duration(seconds: 15),
    );
  }

  // ── 端口转发 ──────────────────────────────────────────────────────────

  Future<bool> forwardPort(int localPort, int remotePort) async {
    final result = await _runDevice(
      <String>['forward', 'tcp:$localPort', 'tcp:$remotePort'],
    );
    return result != null;
  }

  Future<bool> removeForward(int localPort) async {
    final result = await _runDevice(
      <String>['forward', '--remove', 'tcp:$localPort'],
    );
    return result != null;
  }

  // ── 内部实现 ──────────────────────────────────────────────────────────

  List<String> _deviceArgs() {
    if (deviceSerial != null) return <String>['-s', deviceSerial!];
    return const <String>[];
  }

  Future<String?> _run(
    List<String> args, {
    Duration? timeout,
  }) async {
    try {
      final result = await runProcessWithTimeout(
        adbPath,
        args,
        timeout: timeout ?? _kAdbCommandTimeout,
        tag: _kTag,
      );
      if (result == null) return null;
      // Non-zero exit with no stdout → log as warning, still return empty.
      if (result.exitCode != 0 && result.stdout.toString().trim().isEmpty) {
        final stderr = '${result.stderr}'.trim();
        silentLog(
          _kTag,
          'adb ${args.join(' ')} exited ${result.exitCode}${stderr.isNotEmpty ? ": $stderr" : ""}',
          'exitCode=${result.exitCode}',
        );
      }
      return result.stdout.toString().trim();
    } catch (e, st) {
      silentLog(_kTag, 'adb ${args.join(' ')} failed', e, st);
      return null;
    }
  }

  Future<String?> _runDevice(
    List<String> args, {
    Duration? timeout,
  }) {
    return _run(<String>[..._deviceArgs(), ...args], timeout: timeout);
  }
}
