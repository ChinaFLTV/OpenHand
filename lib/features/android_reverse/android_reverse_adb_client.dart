import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../shared/util/input_value_parsing.dart';

const String _kTag = 'android_reverse_adb_client';
const Duration _kAdbCommandTimeout = Duration(seconds: 30);
const Duration _kAdbInstallTimeout = Duration(minutes: 3);
const Duration _kAdbTransferTimeout = Duration(minutes: 5);
const Duration _kAdbPidLookupTimeout = Duration(seconds: 3);
const Duration _kAdbShellQuickReadTimeout = Duration(seconds: 6);
const Duration _kAdbShellReadTimeout = Duration(seconds: 8);
const Duration _kAdbShellDumpsysTimeout = Duration(seconds: 12);
const int _kMaxLogcatLines = 2000;
const int _kMinTcpPort = 1;
const int _kMaxTcpPort = 65535;

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

  bool get hasOutput => stdout.trim().isNotEmpty || stderr.trim().isNotEmpty;

  bool get hasUsableStdout => stdout.trim().isNotEmpty;

  bool get partialOk => timedOut && hasUsableStdout;

  String get commandLine => displayCommand ?? 'adb ${args.join(' ')}';

  String get combinedOutput {
    final out = stdout.trim();
    final err = stderr.trim();
    if (out.isEmpty && err.isEmpty) return '';
    if (out.isEmpty) return err;
    if (err.isEmpty) return out;
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

  bool get found => pid?.trim().isNotEmpty ?? false;
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

  Future<String?> shellLines(List<String> args) async {
    return _runDevice(<String>['shell', ...args]);
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
    if (!_looksLikePackageName(packageName)) return const <String>[];
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
        .toList(growable: false);
    return List<String>.unmodifiable(paths);
  }

  Future<String?> getPackageVersion(String packageName) async {
    if (!_looksLikePackageName(packageName)) return null;
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
    final raw = result.stdout;
    if (raw.trim().isEmpty) return const <String, String>{};
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
    ], timeout: _kAdbInstallTimeout);
    return result != null && result.contains('Success');
  }

  Future<AdbCommandResult> installApkDetailed(
    String localApkPath, {
    bool grantRuntimePermissions = true,
  }) {
    final path = localApkPath.trim();
    if (path.isEmpty) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['install', '<empty-apk-path>'],
          exitCode: -1,
          stdout: '',
          stderr: 'APK path is empty.',
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

  Future<bool> forceStopApp(String packageName) async {
    final result = await shell(
      'am force-stop $packageName',
      timeout: _kAdbShellQuickReadTimeout,
    );
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

  Future<AdbCommandResult> clearPackageDataDetailed(String packageName) {
    if (!_looksLikePackageName(packageName)) {
      return Future<AdbCommandResult>.value(
        AdbCommandResult(
          args: const <String>['shell', 'pm clear <invalid-package>'],
          exitCode: -1,
          stdout: '',
          stderr: 'Invalid Android package name: $packageName',
        ),
      );
    }
    return shellDetailed('pm clear $packageName');
  }

  Future<AdbCommandResult> uninstallPackageDetailed(
    String packageName, {
    bool keepData = false,
  }) {
    if (!_looksLikePackageName(packageName)) {
      return Future<AdbCommandResult>.value(
        AdbCommandResult(
          args: const <String>['uninstall', '<invalid-package>'],
          exitCode: -1,
          stdout: '',
          stderr: 'Invalid Android package name: $packageName',
        ),
      );
    }
    return _runDeviceDetailed(<String>[
      'uninstall',
      if (keepData) '-k',
      packageName,
    ], timeout: _kAdbInstallTimeout);
  }

  Future<bool> startActivity(String packageName, {String? activity}) async {
    if (!_looksLikePackageName(packageName)) return false;
    final activityValue = activity?.trim();
    if (activityValue == null || activityValue.isEmpty) {
      final result = await startPackageDetailed(packageName);
      return result.ok || result.partialOk;
    }
    final component = activityValue.contains('/')
        ? activityValue
        : '$packageName/$activityValue';
    if (!_looksLikeActivityComponent(component)) return false;
    final result = _normalizeLaunchResult(
      await shellDetailed(
        'am start -W -n $component',
        timeout: const Duration(seconds: 12),
      ),
    );
    return result.ok || result.partialOk;
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
      final result = _normalizeLaunchResult(
        await shellDetailed(
          'am start -W -n $launcher',
          timeout: const Duration(seconds: 12),
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
        timeout: const Duration(seconds: 12),
      ),
    );
  }

  // ── 进程管理 ──────────────────────────────────────────────────────────

  Future<List<AndroidProcess>> listProcesses({String? filterName}) async {
    final result = await shellDetailed('ps -A', timeout: _kAdbShellReadTimeout);
    if (!result.ok && !result.hasUsableStdout) {
      return const <AndroidProcess>[];
    }
    return _parseProcessList(result.stdout, filterName: filterName);
  }

  List<AndroidProcess> _parseProcessList(String raw, {String? filterName}) {
    final processes = <AndroidProcess>[];
    final normalizedFilter = nullIfBlank(filterName)?.toLowerCase();
    final lines = raw.split('\n');
    for (final line in lines.skip(1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 9) continue;
      final pid = optionalIntFromValue(parts[1]);
      if (pid == null) continue;
      final name = parts.last;
      if (normalizedFilter != null &&
          !name.toLowerCase().contains(normalizedFilter)) {
        continue;
      }
      processes.add(
        AndroidProcess(
          pid: pid,
          name: name,
          user: parts[0],
          ppid: optionalIntFromValue(parts[2]),
        ),
      );
    }
    return processes;
  }

  Future<String?> pidOfPackage(String packageName) async {
    final result = await pidOfPackageDetailed(packageName);
    return result.pid;
  }

  Future<AndroidPackagePidLookupResult> pidOfPackageDetailed(
    String packageName,
  ) async {
    final normalizedPackageName = packageName.trim();
    if (!_looksLikePackageName(normalizedPackageName)) {
      return AndroidPackagePidLookupResult(
        packageName: normalizedPackageName,
        pid: null,
        timedOut: false,
        stderr: 'Invalid Android package name.',
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
        stderr: direct.stderr.trim(),
      );
    }
    final ps = await _runDeviceDetailed(const <String>[
      'shell',
      'ps',
      '-A',
    ], timeout: _kAdbPidLookupTimeout);
    final procs = _parseProcessList(
      ps.stdout,
      filterName: normalizedPackageName,
    );
    String? pid;
    for (final proc in procs) {
      if (proc.name == normalizedPackageName) {
        pid = '${proc.pid}';
        break;
      }
    }
    pid ??= procs.isEmpty ? null : '${procs.first.pid}';
    return AndroidPackagePidLookupResult(
      packageName: normalizedPackageName,
      pid: pid,
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
          stderr: 'Invalid process id.',
        ),
      );
    }
    return shellDetailed('kill -9 $pid');
  }

  // ── 文件传输 ──────────────────────────────────────────────────────────

  Future<bool> push(String localPath, String remotePath) async {
    final result = await _runDevice(<String>[
      'push',
      localPath,
      remotePath,
    ], timeout: _kAdbTransferTimeout);
    return result != null && !result.toLowerCase().contains('error');
  }

  Future<bool> pull(String remotePath, String localPath) async {
    final result = await _runDevice(<String>[
      'pull',
      remotePath,
      localPath,
    ], timeout: _kAdbTransferTimeout);
    return result != null && !result.toLowerCase().contains('error');
  }

  Future<AdbCommandResult> pushDetailed(String localPath, String remotePath) {
    final local = localPath.trim();
    final remote = remotePath.trim();
    if (local.isEmpty || remote.isEmpty) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['push', '<local>', '<remote>'],
          exitCode: -1,
          stdout: '',
          stderr: 'Both local and remote paths are required.',
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
    final remote = remotePath.trim();
    final local = localPath.trim();
    if (remote.isEmpty || local.isEmpty) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['pull', '<remote>', '<local>'],
          exitCode: -1,
          stdout: '',
          stderr: 'Both remote and local paths are required.',
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
    if (tag != null && tag.trim().isNotEmpty) {
      filter
        ..add('${tag.trim()}:$normalizedLevel')
        ..add('*:S');
    } else if (normalizedLevel != 'V') {
      filter.add('*:$normalizedLevel');
    }
    return _runDeviceDetailed(<String>[
      'logcat',
      '-d',
      '-t',
      '$boundedLines',
      if (pid != null && RegExp(r'^\d+$').hasMatch(pid.trim())) ...[
        '--pid',
        pid.trim(),
      ],
      if (filter.isNotEmpty) ...filter,
    ], timeout: const Duration(seconds: 15));
  }

  Future<AdbCommandResult> clearLogcatDetailed() {
    return _runDeviceDetailed(<String>['logcat', '-c']);
  }

  // ── 端口转发 ──────────────────────────────────────────────────────────

  Future<bool> forwardPort(int localPort, int remotePort) async {
    if (!_isValidTcpPort(localPort) || !_isValidTcpPort(remotePort)) {
      return false;
    }
    final result = await _runDevice(<String>[
      'forward',
      'tcp:$localPort',
      'tcp:$remotePort',
    ]);
    return result != null;
  }

  Future<bool> removeForward(int localPort) async {
    if (!_isValidTcpPort(localPort)) return false;
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
    if (!_isValidTcpPort(localPort) || !_isValidTcpPort(remotePort)) {
      return _invalidPortResult('forward', localPort, remotePort);
    }
    return _runDeviceDetailed(<String>[
      'forward',
      'tcp:$localPort',
      'tcp:$remotePort',
    ]);
  }

  Future<AdbCommandResult> removeForwardDetailed(int localPort) {
    if (!_isValidTcpPort(localPort)) {
      return _invalidPortResult('forward --remove', localPort, null);
    }
    return _runDeviceDetailed(<String>[
      'forward',
      '--remove',
      'tcp:$localPort',
    ]);
  }

  Future<bool> reversePort(int devicePort, int hostPort) async {
    if (!_isValidTcpPort(devicePort) || !_isValidTcpPort(hostPort)) {
      return false;
    }
    final result = await _runDevice(<String>[
      'reverse',
      'tcp:$devicePort',
      'tcp:$hostPort',
    ]);
    return result != null;
  }

  Future<bool> removeReverse(int devicePort) async {
    if (!_isValidTcpPort(devicePort)) return false;
    final result = await _runDevice(<String>[
      'reverse',
      '--remove',
      'tcp:$devicePort',
    ]);
    return result != null;
  }

  Future<String?> listReverses() {
    return _runDevice(<String>['reverse', '--list']);
  }

  Future<bool> removeAllReverses() async {
    final result = await _runDevice(<String>['reverse', '--remove-all']);
    return result != null;
  }

  Future<AdbCommandResult> reversePortDetailed(int devicePort, int hostPort) {
    if (!_isValidTcpPort(devicePort) || !_isValidTcpPort(hostPort)) {
      return _invalidPortResult('reverse', devicePort, hostPort);
    }
    return _runDeviceDetailed(<String>[
      'reverse',
      'tcp:$devicePort',
      'tcp:$hostPort',
    ]);
  }

  Future<AdbCommandResult> removeReverseDetailed(int devicePort) {
    if (!_isValidTcpPort(devicePort)) {
      return _invalidPortResult('reverse --remove', devicePort, null);
    }
    return _runDeviceDetailed(<String>[
      'reverse',
      '--remove',
      'tcp:$devicePort',
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

  Future<AdbCommandResult> tcpip(int port) {
    if (port <= 0 || port > 65535) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['tcpip', '<invalid-port>'],
          exitCode: -1,
          stdout: '',
          stderr: 'Invalid TCP/IP port.',
        ),
      );
    }
    return _runDeviceDetailed(<String>['tcpip', '$port']);
  }

  Future<AdbCommandResult> captureScreenshotDetailed(String remotePath) {
    final path = remotePath.trim();
    if (path.isEmpty) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['shell', 'screencap -p <remote-path>'],
          exitCode: -1,
          stdout: '',
          stderr: 'Remote screenshot path is empty.',
        ),
      );
    }
    final quoted = _quoteShell(path);
    return shellDetailed(
      'mkdir -p ${_quoteShell(_remoteParent(path))}; '
      'screencap -p $quoted; '
      'ls -l $quoted',
      timeout: const Duration(seconds: 12),
    );
  }

  Future<AdbCommandResult> screenRecordDetailed(
    String remotePath, {
    int seconds = 10,
  }) {
    final path = remotePath.trim();
    if (path.isEmpty || seconds <= 0 || seconds > 180) {
      return Future<AdbCommandResult>.value(
        const AdbCommandResult(
          args: <String>['shell', 'screenrecord --time-limit <seconds> <path>'],
          exitCode: -1,
          stdout: '',
          stderr: 'Remote recording path or duration is invalid.',
        ),
      );
    }
    final quoted = _quoteShell(path);
    return shellDetailed(
      'mkdir -p ${_quoteShell(_remoteParent(path))}; '
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
    StreamSubscription<String>? stdoutSub;
    StreamSubscription<String>? stderrSub;
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    void complete(Completer<void> completer) {
      if (!completer.isCompleted) completer.complete();
    }

    Future<void> drainOutput() async {
      await Future.wait<void>(<Future<void>>[
        stdoutDone.future,
        stderrDone.future,
      ]).timeout(const Duration(milliseconds: 350), onTimeout: () => <void>[]);
      if (!stdoutDone.isCompleted) await stdoutSub?.cancel();
      if (!stderrDone.isCompleted) await stderrSub?.cancel();
    }

    try {
      process = await startTrackedProcess(adbPath, args);
      stdoutSub = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            stdoutBuffer.write,
            onError: (Object error, StackTrace stackTrace) {
              complete(stdoutDone);
            },
            onDone: () => complete(stdoutDone),
          );
      stderrSub = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            stderrBuffer.write,
            onError: (Object error, StackTrace stackTrace) {
              complete(stderrDone);
            },
            onDone: () => complete(stderrDone),
          );
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
      await drainOutput();
      final stdout = stdoutBuffer.toString();
      var stderr = stderrBuffer.toString();
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
      await stdoutSub?.cancel();
      await stderrSub?.cancel();
      silentLog(_kTag, 'adb ${args.join(' ')} failed', e, st);
      final stdout = stdoutBuffer.toString();
      final stderr = stderrBuffer.toString().trim();
      return AdbCommandResult(
        args: List<String>.unmodifiable(args),
        exitCode: -1,
        stdout: stdout,
        stderr: stderr.isEmpty ? '$e' : '$stderr\n$e',
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

  List<String>? _shellCommandArgs(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return null;
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
        stderr: 'ADB shell command is empty.',
      ),
    );
  }

  bool _isValidTcpPort(int value) =>
      value >= _kMinTcpPort && value <= _kMaxTcpPort;

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
        stderr: 'TCP port must be between $_kMinTcpPort and $_kMaxTcpPort.',
      ),
    );
  }

  bool _looksLikePackageName(String value) {
    final packageName = value.trim();
    if (packageName.length > 220) return false;
    return RegExp(
      r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
    ).hasMatch(packageName);
  }

  bool _looksLikeActivityComponent(String value) {
    final component = value.trim();
    if (component.length > 320) return false;
    return RegExp(
      r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+/(\.[A-Za-z0-9_.$]+|[A-Za-z][A-Za-z0-9_.$]*)$',
    ).hasMatch(component);
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
    if (raw == null) return null;
    final match = RegExp(r'\b\d+\b').firstMatch(raw);
    return match?.group(0);
  }

  String _combineAdbErrors(List<AdbCommandResult> results) {
    final errors = <String>{};
    for (final result in results) {
      final stderr = result.stderr.trim();
      if (stderr.isNotEmpty) {
        errors.add(stderr);
      }
    }
    return errors.join('\n');
  }

  String _normalizeLogcatLevel(String? raw) {
    final value = (raw ?? 'V').trim().toUpperCase();
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
    final warning = result.stderr.trim().isEmpty
        ? 'ADB shell did not close after launch output; treated as success from stdout.'
        : '${result.stderr.trim()}\nADB shell did not close after launch output; treated as success from stdout.';
    return result.copyWith(exitCode: 0, stderr: warning, timedOut: false);
  }

  String _remoteParent(String path) {
    final normalized = path.trim();
    final slash = normalized.lastIndexOf('/');
    if (slash <= 0) return '/sdcard';
    return normalized.substring(0, slash);
  }

  String _quoteShell(String value) {
    if (RegExp(r'^[A-Za-z0-9_./:@%+=,-]+$').hasMatch(value)) {
      return value;
    }
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }
}
