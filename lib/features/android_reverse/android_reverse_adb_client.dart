import 'dart:convert';
import 'dart:io';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../shared/net/tcp_port_utils.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/platform_shell.dart';
import '../../shared/util/text_normalization.dart';
import 'android_reverse_session_config.dart';

const String _kTag = 'android_reverse_adb_client';
const Duration _kAdbCommandTimeout = Duration(seconds: 30);
const Duration _kAdbInstallTimeout = Duration(minutes: 3);
const Duration _kAdbTransferTimeout = Duration(minutes: 5);
const Duration _kAdbPidLookupTimeout = Duration(seconds: 3);
const Duration _kAdbShellReadTimeout = Duration(seconds: 8);
const Duration _kAdbShellDumpsysTimeout = Duration(seconds: 12);

/// 拉起应用：am start / monkey 要等界面真正启动。
const Duration _kAdbAppLaunchTimeout = Duration(seconds: 12);

/// 截屏并回读文件列表，耗时随屏幕分辨率变化。
const Duration _kAdbScreencapTimeout = Duration(seconds: 12);

/// logcat 批量导出，行数上限内一次读完。
const Duration _kAdbLogcatTimeout = Duration(seconds: 15);
const int _kMaxAdbStdoutBytes = 4 * kBytesPerMiB;
const int _kMaxAdbStderrBytes = 512 * kBytesPerKiB;
const int _kMaxLogcatLines = 2000;
const int _kMaxPackageApkPaths = 64;
const int _kMinTcpPort = kTcpPortMin;
const int _kMaxTcpPort = kTcpPortMax;
const String _kInvalidAndroidPackageMessage = 'Android 包名无效。';

class AdbCommandResult {
  const AdbCommandResult({
    required this.args,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
    this.displayCommand,
  });

  final List<String> args;
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final String? displayCommand;

  bool get ok => exitCode == 0 && !timedOut;

  bool get hasOutput =>
      nullIfBlank(stdout) != null || nullIfBlank(stderr) != null;

  bool get hasUsableStdout => nullIfBlank(stdout) != null;

  bool get partialOk => timedOut && hasUsableStdout;

  String get commandLine => displayCommand ?? 'adb ${args.join(' ')}';

  String get combinedOutput {
    final out = nullIfBlank(stdout);
    final err = nullIfBlank(stderr);
    if (out == null && err == null) return '';
    if (out == null) return err!;
    if (err == null) return out;
    return '$out\n$err';
  }

  AdbCommandResult copyWith({
    int? exitCode,
    String? stdout,
    String? stderr,
    bool? timedOut,
    String? displayCommand,
  }) {
    return AdbCommandResult(
      args: args,
      exitCode: exitCode ?? this.exitCode,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      timedOut: timedOut ?? this.timedOut,
      displayCommand: displayCommand ?? this.displayCommand,
    );
  }
}

/// 修正 `adb connect` 失败时仍返回退出码 0 的平台工具行为。
AdbCommandResult normalizeAdbConnectResult(AdbCommandResult result) {
  if (!result.ok) return result;
  final output = result.combinedOutput.toLowerCase();
  final connected = output.contains('connected to ');
  if (connected) return result;
  final message =
      nullIfBlank(result.stderr) ??
      nullIfBlank(result.stdout) ??
      'ADB 连接未返回成功结果。';
  return result.copyWith(exitCode: -1, stdout: '', stderr: message);
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

/// 解析不同 Android 版本和厂商实现输出的 `ps` 进程列表。
List<AndroidProcess> parseAndroidProcessList(String raw, {String? filterName}) {
  final lines = splitTrimmedNonEmpty(raw, separator: '\n');
  if (lines.isEmpty) return const <AndroidProcess>[];

  final header = lines.first.split(kInlineWhitespacePattern);
  final normalizedHeader = header.map((value) => value.toUpperCase()).toList();
  final pidIndex = normalizedHeader.indexOf('PID');
  final hasHeader = pidIndex >= 0;
  final userIndex = hasHeader ? normalizedHeader.indexOf('USER') : 0;
  final ppidIndex = hasHeader ? normalizedHeader.indexOf('PPID') : 2;
  final nameIndex = hasHeader
      ? <String>['NAME', 'CMDLINE', 'CMD', 'COMMAND', 'ARGS']
            .map(normalizedHeader.indexOf)
            .firstWhere((index) => index >= 0, orElse: () => -1)
      : -1;
  final normalizedFilter = nullIfBlank(filterName)?.toLowerCase();
  final processes = <AndroidProcess>[];

  for (final line in lines.skip(hasHeader ? 1 : 0)) {
    final parts = line.split(kInlineWhitespacePattern);
    final resolvedPidIndex = hasHeader ? pidIndex : (parts.length > 1 ? 1 : -1);
    if (resolvedPidIndex < 0 || resolvedPidIndex >= parts.length) continue;
    final pid = optionalIntFromValue(parts[resolvedPidIndex]);
    if (pid == null || pid <= 0) continue;

    final resolvedNameIndex = nameIndex >= 0 && nameIndex < parts.length
        ? nameIndex
        : parts.length - 1;
    final name = parts[resolvedNameIndex].trim();
    if (name.isEmpty ||
        (normalizedFilter != null &&
            !name.toLowerCase().contains(normalizedFilter))) {
      continue;
    }
    processes.add(
      AndroidProcess(
        pid: pid,
        name: name,
        user: userIndex >= 0 && userIndex < parts.length
            ? nullIfBlank(parts[userIndex])
            : null,
        ppid: ppidIndex >= 0 && ppidIndex < parts.length
            ? optionalIntFromValue(parts[ppidIndex])
            : null,
      ),
    );
  }
  return List<AndroidProcess>.unmodifiable(processes);
}

class AndroidPackagePidLookupResult {
  const AndroidPackagePidLookupResult({
    required this.packageName,
    required this.pid,
    required this.timedOut,
    required this.stderr,
  });

  final String packageName;
  final String? pid;
  final bool timedOut;
  final String stderr;

  bool get found => nullIfBlank(pid) != null;
}

/// 精简 ADB 客户端，封装 `adb` 命令行调用。
///
/// 所有操作均通过 `adb` 可执行文件完成；调用方需确保 adb 已在 PATH 中
/// 或通过 [adbPath] 显式指定路径。
class AndroidReverseAdbClient {
  AndroidReverseAdbClient({String? adbPath, String? deviceSerial})
    : adbPath = nullIfBlank(adbPath) ?? 'adb',
      deviceSerial = nullIfBlank(deviceSerial);

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
      final parts = trimmed.split(kInlineWhitespacePattern);
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

  AdbDevice? selectOnlineDevice(Iterable<AdbDevice> devices) {
    if (deviceSerial != null) {
      return devices
          .where((d) => d.serial == deviceSerial && d.isOnline)
          .firstOrNull;
    }
    final online = devices.where((d) => d.isOnline).toList(growable: false);
    return online.length == 1 ? online.first : null;
  }

  // ── 基本 Shell 命令 ───────────────────────────────────────────────────

  Future<String?> shell(String command, {Duration? timeout}) async {
    final args = _shellCommandArgs(command);
    if (args == null) return null;
    return _runDevice(args, timeout: timeout);
  }

  Future<AdbCommandResult> shellDetailed(String command, {Duration? timeout}) {
    final args = _shellCommandArgs(command);
    if (args == null) return _emptyShellCommandResult();
    return _runDeviceDetailed(args, timeout: timeout);
  }

  // ── APP 管理 ──────────────────────────────────────────────────────────

  Future<List<String>> listPackages({bool thirdParty = true}) async {
    final flag = thirdParty ? '-3' : '';
    final result = await shellDetailed(
      'pm list packages $flag'.trim(),
      timeout: _kAdbShellReadTimeout,
    );
    if (!result.ok && !result.hasUsableStdout) return const <String>[];
    final raw = result.stdout;
    final packages = splitTrimmedNonEmpty(raw, separator: '\n')
        .where((line) => line.startsWith('package:'))
        .map((line) => line.substring(8))
        .where((line) => line.isNotEmpty)
        .toList();
    packages.sort();
    return List<String>.unmodifiable(packages);
  }

  Future<String?> getPackagePath(String packageName) async {
    final paths = await getPackagePaths(packageName);
    return paths.firstOrNull;
  }

  Future<List<String>> getPackagePaths(String packageName) async {
    if (!looksLikeAndroidPackageName(packageName)) return const <String>[];
    final result = await shellDetailed(
      'pm path $packageName',
      timeout: _kAdbShellReadTimeout,
    );
    if (!result.ok && !result.hasUsableStdout) return const <String>[];
    final raw = result.stdout;
    final paths = splitTrimmedNonEmpty(raw, separator: '\n')
        .where((line) => line.startsWith('package:'))
        .map((line) => line.substring(8).trim())
        .where((line) => line.isNotEmpty)
        .take(_kMaxPackageApkPaths)
        .toList(growable: false);
    return List<String>.unmodifiable(paths);
  }

  Future<String?> getPackageVersion(String packageName) async {
    if (!looksLikeAndroidPackageName(packageName)) return null;
    final result = await shellDetailed(
      'dumpsys package $packageName',
      timeout: _kAdbShellDumpsysTimeout,
    );
    if (!result.ok && !result.hasUsableStdout) return null;
    final raw = result.stdout;
    String? versionName;
    String? versionCode;
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('versionName=')) {
        versionName = trimmed.substring(12).trim();
      } else if (trimmed.startsWith('versionCode=')) {
        versionCode = trimmed
            .substring(12)
            .split(kInlineWhitespacePattern)
            .first
            .trim();
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
    if (!looksLikeAndroidPackageName(packageName)) return null;
    final commands = <String>[
      'cmd package resolve-activity --brief '
          '-a android.intent.action.MAIN '
          '-c android.intent.category.LAUNCHER '
          '-p $packageName',
      'cmd package resolve-activity --brief $packageName',
    ];
    for (final command in commands) {
      final result = await shellDetailed(
        command,
        timeout: _kAdbShellReadTimeout,
      );
      if (!result.ok && !result.hasUsableStdout) continue;
      final launcher = _launcherActivityFromResolveOutput(
        result.stdout,
        packageName,
      );
      if (launcher != null) return launcher;
    }
    return null;
  }

  Future<Map<String, String>> getProperties() async {
    final result = await shellDetailed(
      'getprop',
      timeout: _kAdbShellReadTimeout,
    );
    if (!result.ok && !result.hasUsableStdout) {
      return const <String, String>{};
    }
    final raw = nullIfBlank(result.stdout);
    if (raw == null) return const <String, String>{};
    final props = <String, String>{};
    final pattern = RegExp(r'^\[([^\]]+)\]: \[(.*)\]$');
    for (final line in raw.split('\n')) {
      final match = pattern.firstMatch(line.trim());
      if (match == null) continue;
      props[match.group(1)!] = match.group(2) ?? '';
    }
    return props;
  }

  Future<AdbCommandResult> installApkDetailed(
    String localApkPath, {
    bool grantRuntimePermissions = true,
  }) {
    final path = nullIfBlank(localApkPath);
    if (path == null) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['install', '<empty-apk-path>'],
          exitCode: -1,
          stdout: '',
          stderr: 'APK 路径为空。',
        ),
      );
    }
    return _runDeviceDetailed(<String>[
      'install',
      '-r',
      if (grantRuntimePermissions) '-g',
      path,
    ], timeout: _kAdbInstallTimeout);
  }

  Future<AdbCommandResult> forceStopAppDetailed(String packageName) {
    if (!looksLikeAndroidPackageName(packageName)) {
      return Future<AdbCommandResult>.value(
        AdbCommandResult(
          args: const <String>['shell', 'am force-stop <invalid-package>'],
          exitCode: -1,
          stdout: '',
          stderr: '$_kInvalidAndroidPackageMessage：$packageName',
        ),
      );
    }
    return shellDetailed('am force-stop $packageName');
  }

  Future<AdbCommandResult> clearPackageDataDetailed(String packageName) {
    if (!looksLikeAndroidPackageName(packageName)) {
      return Future<AdbCommandResult>.value(
        AdbCommandResult(
          args: const <String>['shell', 'pm clear <invalid-package>'],
          exitCode: -1,
          stdout: '',
          stderr: '$_kInvalidAndroidPackageMessage：$packageName',
        ),
      );
    }
    return shellDetailed('pm clear $packageName');
  }

  Future<AdbCommandResult> uninstallPackageDetailed(
    String packageName, {
    bool keepData = false,
  }) {
    if (!looksLikeAndroidPackageName(packageName)) {
      return Future<AdbCommandResult>.value(
        AdbCommandResult(
          args: const <String>['uninstall', '<invalid-package>'],
          exitCode: -1,
          stdout: '',
          stderr: '$_kInvalidAndroidPackageMessage：$packageName',
        ),
      );
    }
    return _runDeviceDetailed(<String>[
      'uninstall',
      if (keepData) '-k',
      packageName,
    ], timeout: _kAdbInstallTimeout);
  }

  Future<AdbCommandResult> startPackageDetailed(String packageName) async {
    if (!looksLikeAndroidPackageName(packageName)) {
      return AdbCommandResult(
        args: const <String>['shell', 'monkey -p <invalid-package>'],
        exitCode: -1,
        stdout: '',
        stderr: '$_kInvalidAndroidPackageMessage：$packageName',
      );
    }
    final launcher = await resolveLauncherActivity(packageName);
    if (launcher != null && launcher.isNotEmpty) {
      final result = _normalizeLaunchResult(
        await shellDetailed(
          'am start -W -n $launcher',
          timeout: _kAdbAppLaunchTimeout,
        ),
      );
      final output = result.combinedOutput.toLowerCase();
      if (!output.contains('error type 3') &&
          !output.contains('does not exist')) {
        return result;
      }
    }
    return _normalizeLaunchResult(
      await shellDetailed(
        'monkey -p $packageName -c android.intent.category.LAUNCHER 1',
        timeout: _kAdbAppLaunchTimeout,
      ),
    );
  }

  // ── 进程管理 ──────────────────────────────────────────────────────────

  Future<List<AndroidProcess>> listProcesses({String? filterName}) async {
    final result = await shellDetailed('ps -A', timeout: _kAdbShellReadTimeout);
    if (!result.ok && !result.hasUsableStdout) {
      return const <AndroidProcess>[];
    }
    return parseAndroidProcessList(result.stdout, filterName: filterName);
  }

  Future<String?> pidOfPackage(String packageName) async {
    final result = await pidOfPackageDetailed(packageName);
    return result.pid;
  }

  Future<AndroidPackagePidLookupResult> pidOfPackageDetailed(
    String packageName,
  ) async {
    final normalizedPackageName = nullIfBlank(packageName) ?? '';
    if (!looksLikeAndroidPackageName(normalizedPackageName)) {
      return AndroidPackagePidLookupResult(
        packageName: normalizedPackageName,
        pid: null,
        timedOut: false,
        stderr: _kInvalidAndroidPackageMessage,
      );
    }
    final direct = await _runDeviceDetailed(<String>[
      'shell',
      'pidof',
      normalizedPackageName,
    ], timeout: _kAdbPidLookupTimeout);
    final directPid = _firstPidFromText(direct.stdout);
    if (directPid != null) {
      return AndroidPackagePidLookupResult(
        packageName: normalizedPackageName,
        pid: directPid,
        timedOut: direct.timedOut,
        stderr: nullIfBlank(direct.stderr) ?? '',
      );
    }
    final ps = await _runDeviceDetailed(const <String>[
      'shell',
      'ps',
      '-A',
    ], timeout: _kAdbPidLookupTimeout);
    final procs = parseAndroidProcessList(ps.stdout);
    AndroidProcess? matchedProcess;
    for (final proc in procs) {
      if (proc.name == normalizedPackageName) {
        matchedProcess = proc;
        break;
      }
      if (matchedProcess == null &&
          proc.name.startsWith('$normalizedPackageName:')) {
        matchedProcess = proc;
      }
    }
    return AndroidPackagePidLookupResult(
      packageName: normalizedPackageName,
      pid: matchedProcess?.pid.toString(),
      timedOut: direct.timedOut || ps.timedOut,
      stderr: _combineAdbErrors(<AdbCommandResult>[direct, ps]),
    );
  }

  Future<AdbCommandResult> killProcessDetailed(int pid) {
    if (pid <= 0) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['shell', 'kill -9 <invalid-pid>'],
          exitCode: -1,
          stdout: '',
          stderr: '进程 ID 无效。',
        ),
      );
    }
    return shellDetailed('kill -9 $pid');
  }

  // ── 文件传输 ──────────────────────────────────────────────────────────

  Future<bool> push(String localPath, String remotePath) async =>
      (await pushDetailed(localPath, remotePath)).ok;

  Future<bool> pull(String remotePath, String localPath) async =>
      (await pullDetailed(remotePath, localPath)).ok;

  Future<AdbCommandResult> pushDetailed(String localPath, String remotePath) {
    final local = nullIfBlank(localPath);
    final remote = nullIfBlank(remotePath);
    if (local == null || remote == null) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['push', '<local>', '<remote>'],
          exitCode: -1,
          stdout: '',
          stderr: '本地路径和远程路径均不能为空。',
        ),
      );
    }
    return _runDeviceDetailed(<String>[
      'push',
      local,
      remote,
    ], timeout: _kAdbTransferTimeout);
  }

  Future<AdbCommandResult> pullDetailed(String remotePath, String localPath) {
    final remote = nullIfBlank(remotePath);
    final local = nullIfBlank(localPath);
    if (remote == null || local == null) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['pull', '<remote>', '<local>'],
          exitCode: -1,
          stdout: '',
          stderr: '远程路径和本地路径均不能为空。',
        ),
      );
    }
    return _runDeviceDetailed(<String>[
      'pull',
      remote,
      local,
    ], timeout: _kAdbTransferTimeout);
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
    String? pid,
  }) {
    final filter = <String>[];
    final boundedLines = lines.clamp(1, _kMaxLogcatLines).toInt();
    final normalizedLevel = _normalizeLogcatLevel(level);
    final normalizedTag = nullIfBlank(tag);
    final normalizedPid = nullIfBlank(pid);
    if (normalizedTag != null) {
      filter
        ..add('$normalizedTag:$normalizedLevel')
        ..add('*:S');
    } else if (normalizedLevel != 'V') {
      filter.add('*:$normalizedLevel');
    }
    return _runDeviceDetailed(<String>[
      'logcat',
      '-d',
      '-t',
      '$boundedLines',
      if (normalizedPid != null &&
          RegExp(r'^\d+$').hasMatch(normalizedPid)) ...[
        '--pid',
        normalizedPid,
      ],
      if (filter.isNotEmpty) ...filter,
    ], timeout: _kAdbLogcatTimeout);
  }

  Future<AdbCommandResult> clearLogcatDetailed() {
    return _runDeviceDetailed(<String>['logcat', '-c']);
  }

  // ── 端口转发 ──────────────────────────────────────────────────────────

  Future<bool> forwardPort(int localPort, int remotePort) async =>
      (await forwardPortDetailed(localPort, remotePort)).ok;

  Future<bool> removeForward(int localPort) async =>
      (await removeForwardDetailed(localPort)).ok;

  Future<String?> listForwards() {
    return _runDevice(<String>['forward', '--list']);
  }

  Future<bool> removeAllForwards() async {
    final result = await _runDeviceDetailed(<String>[
      'forward',
      '--remove-all',
    ]);
    return result.ok;
  }

  Future<AdbCommandResult> forwardPortDetailed(int localPort, int remotePort) {
    if (!isValidTcpPort(localPort) || !isValidTcpPort(remotePort)) {
      return _invalidPortResult('forward', localPort, remotePort);
    }
    return _runDeviceDetailed(<String>[
      'forward',
      'tcp:$localPort',
      'tcp:$remotePort',
    ]);
  }

  Future<AdbCommandResult> removeForwardDetailed(int localPort) {
    if (!isValidTcpPort(localPort)) {
      return _invalidPortResult('forward --remove', localPort, null);
    }
    return _runDeviceDetailed(<String>[
      'forward',
      '--remove',
      'tcp:$localPort',
    ]);
  }

  Future<bool> reversePort(int devicePort, int hostPort) async =>
      (await reversePortDetailed(devicePort, hostPort)).ok;

  Future<bool> removeReverse(int devicePort) async =>
      (await removeReverseDetailed(devicePort)).ok;

  Future<String?> listReverses() {
    return _runDevice(<String>['reverse', '--list']);
  }

  Future<bool> removeAllReverses() async {
    final result = await _runDeviceDetailed(<String>[
      'reverse',
      '--remove-all',
    ]);
    return result.ok;
  }

  Future<AdbCommandResult> reversePortDetailed(int devicePort, int hostPort) {
    if (!isValidTcpPort(devicePort) || !isValidTcpPort(hostPort)) {
      return _invalidPortResult('reverse', devicePort, hostPort);
    }
    return _runDeviceDetailed(<String>[
      'reverse',
      'tcp:$devicePort',
      'tcp:$hostPort',
    ]);
  }

  Future<AdbCommandResult> removeReverseDetailed(int devicePort) {
    if (!isValidTcpPort(devicePort)) {
      return _invalidPortResult('reverse --remove', devicePort, null);
    }
    return _runDeviceDetailed(<String>[
      'reverse',
      '--remove',
      'tcp:$devicePort',
    ]);
  }

  Future<AdbCommandResult> connect(String endpoint) async {
    final normalizedEndpoint = nullIfBlank(endpoint);
    if (normalizedEndpoint == null) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['connect', '<empty-endpoint>'],
          exitCode: -1,
          stdout: '',
          stderr: 'ADB 连接地址为空。',
        ),
      );
    }
    return normalizeAdbConnectResult(
      await _runDetailed(<String>['connect', normalizedEndpoint]),
    );
  }

  Future<AdbCommandResult> disconnect([String? endpoint]) {
    final normalizedEndpoint = nullIfBlank(endpoint);
    return _runDetailed(<String>[
      'disconnect',
      if (normalizedEndpoint != null) normalizedEndpoint,
    ]);
  }

  Future<AdbCommandResult> reboot([String? mode]) {
    final normalizedMode = nullIfBlank(mode);
    return _runDeviceDetailed(<String>[
      'reboot',
      if (normalizedMode != null) normalizedMode,
    ]);
  }

  Future<AdbCommandResult> root() => _runDeviceDetailed(<String>['root']);

  Future<AdbCommandResult> remount() => _runDeviceDetailed(<String>['remount']);

  Future<AdbCommandResult> tcpip(int port) {
    if (!isValidTcpPort(port)) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['tcpip', '<invalid-port>'],
          exitCode: -1,
          stdout: '',
          stderr: 'TCP/IP 端口无效。',
        ),
      );
    }
    return _runDeviceDetailed(<String>['tcpip', '$port']);
  }

  Future<AdbCommandResult> captureScreenshotDetailed(String remotePath) {
    final path = nullIfBlank(remotePath);
    if (path == null) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['shell', 'screencap -p <remote-path>'],
          exitCode: -1,
          stdout: '',
          stderr: '远程截图路径为空。',
        ),
      );
    }
    final quoted = posixShellQuoteIfNeeded(path);
    return shellDetailed(
      'mkdir -p ${posixShellQuoteIfNeeded(_remoteParent(path))}; '
      'screencap -p $quoted; '
      'ls -l $quoted',
      timeout: _kAdbScreencapTimeout,
    );
  }

  Future<AdbCommandResult> screenRecordDetailed(
    String remotePath, {
    int seconds = 10,
  }) {
    final path = nullIfBlank(remotePath);
    if (path == null || seconds <= 0 || seconds > 180) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['shell', 'screenrecord --time-limit <seconds> <path>'],
          exitCode: -1,
          stdout: '',
          stderr: '远程录屏路径或时长无效。',
        ),
      );
    }
    final quoted = posixShellQuoteIfNeeded(path);
    return shellDetailed(
      'mkdir -p ${posixShellQuoteIfNeeded(_remoteParent(path))}; '
      'screenrecord --time-limit $seconds $quoted; '
      'ls -l $quoted',
      timeout: Duration(seconds: seconds + 12),
    );
  }

  // ── 内部实现 ──────────────────────────────────────────────────────────

  List<String> _deviceArgs() {
    if (deviceSerial != null) return <String>['-s', deviceSerial!];
    return const <String>[];
  }

  Future<String?> _run(List<String> args, {Duration? timeout}) async {
    final result = await _runDetailed(args, timeout: timeout);
    if (result.timedOut && !result.hasUsableStdout) return null;
    if (!result.ok && !result.hasUsableStdout) {
      final stderr = nullIfBlank(result.stderr);
      silentLog(
        _kTag,
        '执行 adb ${args.join(' ')}，退出码 ${result.exitCode}${stderr == null ? "" : "：$stderr"}',
        'exitCode=${result.exitCode}',
      );
      return null;
    }
    return result.stdout.trim();
  }

  Future<AdbCommandResult> _runDetailed(
    List<String> args, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _kAdbCommandTimeout;
    var timedOut = false;
    Object? failure;
    final result = await runProcessWithTimeout(
      adbPath,
      args,
      timeout: effectiveTimeout,
      tag: _kTag,
      maxStdoutBytes: _kMaxAdbStdoutBytes,
      maxStderrBytes: _kMaxAdbStderrBytes,
      onFailure: (error, _) => failure = error,
      timeoutResultBuilder: (pid, stdout, stderr) {
        timedOut = true;
        return ProcessResult(pid, -1, stdout, stderr);
      },
    );
    if (result == null) {
      final error = failure ?? 'ADB 命令未能返回结果。';
      return AdbCommandResult(
        args: List<String>.unmodifiable(args),
        exitCode: -1,
        stdout: '',
        stderr: '$error',
      );
    }
    final stdout = result.stdout as String;
    var stderr = result.stderr as String;
    if (timedOut && nullIfBlank(stderr) == null) {
      stderr = 'ADB 命令执行超时。';
    }
    return AdbCommandResult(
      args: List<String>.unmodifiable(args),
      exitCode: result.exitCode,
      stdout: stdout,
      stderr: stderr,
      timedOut: timedOut,
    );
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

  List<String>? _shellCommandArgs(String command) {
    final trimmed = nullIfBlank(command);
    if (trimmed == null) return null;
    final wrapped = trimmed.endsWith('\nexit') || trimmed.endsWith('\nexit\n')
        ? trimmed
        : '$trimmed\nexit';
    return <String>['shell', wrapped];
  }

  Future<AdbCommandResult> _emptyShellCommandResult() {
    return Future<AdbCommandResult>.value(
      const AdbCommandResult(
        args: <String>['shell', '<empty-command>'],
        exitCode: -1,
        stdout: '',
        stderr: 'ADB shell 命令为空。',
      ),
    );
  }

  Future<AdbCommandResult> _invalidPortResult(
    String command,
    int firstPort,
    int? secondPort,
  ) {
    return Future<AdbCommandResult>.value(
      AdbCommandResult(
        args: <String>[
          command,
          'tcp:$firstPort',
          if (secondPort != null) 'tcp:$secondPort',
        ],
        exitCode: -1,
        stdout: '',
        stderr: 'TCP 端口必须在 $_kMinTcpPort 至 $_kMaxTcpPort 之间。',
      ),
    );
  }

  String? _launcherActivityFromResolveOutput(String raw, String packageName) {
    final lines = splitTrimmedNonEmpty(raw, separator: '\n').reversed;
    for (final line in lines) {
      if (line.isEmpty || !line.contains('/')) continue;
      final lower = line.toLowerCase();
      if (lower.contains('no activity') ||
          lower.contains('unable to resolve')) {
        continue;
      }
      final match = RegExp(
        r'([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+/[A-Za-z0-9_.$]+)',
      ).firstMatch(line);
      final component = match?.group(1) ?? line;
      if (!component.startsWith(packageName) && !component.startsWith('/')) {
        continue;
      }
      return component.startsWith('/') ? '$packageName$component' : component;
    }
    return null;
  }

  String? _firstPidFromText(String? raw) {
    final text = nullIfBlank(raw);
    if (text == null) return null;
    final match = RegExp(r'\b\d+\b').firstMatch(text);
    return match?.group(0);
  }

  String _combineAdbErrors(List<AdbCommandResult> results) {
    final errors = <String>{};
    for (final result in results) {
      final stderr = nullIfBlank(result.stderr);
      if (stderr != null) {
        errors.add(stderr);
      }
    }
    return errors.join('\n');
  }

  String _normalizeLogcatLevel(String? raw) {
    final value = (nullIfBlank(raw) ?? 'V').toUpperCase();
    return const <String>{'V', 'D', 'I', 'W', 'E', 'F'}.contains(value)
        ? value
        : 'V';
  }

  AdbCommandResult _normalizeLaunchResult(AdbCommandResult result) {
    if (!result.timedOut || !result.hasUsableStdout) return result;
    final output = result.stdout.toLowerCase();
    final launchCompleted =
        output.contains('events injected: 1') ||
        output.contains('status: ok') ||
        output.contains('complete');
    final launchFailed =
        output.contains('error type') ||
        output.contains('does not exist') ||
        output.contains('exception') ||
        output.contains('unable to resolve intent');
    if (!launchCompleted || launchFailed) return result;
    final stderr = nullIfBlank(result.stderr);
    final warning = stderr == null
        ? 'ADB shell 返回启动输出后未退出，已根据标准输出判定为成功。'
        : '$stderr\nADB shell 返回启动输出后未退出，已根据标准输出判定为成功。';
    return result.copyWith(exitCode: 0, stderr: warning, timedOut: false);
  }

  String _remoteParent(String path) {
    final normalized = nullIfBlank(path) ?? '';
    final slash = normalized.lastIndexOf('/');
    if (slash <= 0) return kAndroidSdCardRoot;
    return normalized.substring(0, slash);
  }
}
