import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../shared/util/byte_size_format.dart';
import 'openhand_paths.dart';
import 'safe_subprocess.dart';
import 'silent_log.dart';

/// 无法安全完成单实例接管时抛出，调用方应终止本次启动。
final class OpenHandSingleInstanceException implements Exception {
  const OpenHandSingleInstanceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 在桌面端启动早期回收旧实例，并登记当前实例以覆盖不同安装路径的接管。
final class OpenHandSingleInstance {
  OpenHandSingleInstance._(this._recordFile, this._token);

  static const String _recordPrefix = 'instance-';
  static const String _recordSuffix = '.json';
  static const String _temporaryRecordSuffix = '.tmp';
  static const String _applicationId = 'com.flwork.openhand';
  static const int _recordVersion = 1;
  static const int _maxInstanceRecords = 128;
  static const int _maxTrackedDescendants = 256;
  static const int _maxProcessListBytes = 4 * kBytesPerMiB;
  static const int _maxMacInfoPlistBytes = kBytesPerMiB;
  static const Duration _fileOperationTimeout = Duration(seconds: 2);
  static const Duration _processQueryTimeout = Duration(seconds: 3);
  static const Duration _takeoverLockTimeout = Duration(seconds: 8);
  static const Duration _gracefulExitTimeout = Duration(seconds: 8);
  static const Duration _residualExitTimeout = Duration(milliseconds: 800);
  static const Duration _forcedExitTimeout = Duration(seconds: 2);
  static const Duration _takeoverRetryDelay = Duration(milliseconds: 50);
  static const Duration _processPollMinDelay = Duration(milliseconds: 60);
  static const Duration _processPollMaxDelay = Duration(milliseconds: 400);

  final File? _recordFile;
  final String _token;
  Future<void>? _disposeFuture;

  static bool get _supportedDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// 新实例优先：串行回收此前实例及其后代，成功后才允许继续初始化。
  static Future<OpenHandSingleInstance> acquire() async {
    if (!_supportedDesktop) {
      return OpenHandSingleInstance._(null, '');
    }

    final runtimeDirectory = Directory(
      p.join(OpenHandPaths.defaultRootDirectoryPath(), 'runtime'),
    );
    final instancesDirectory = Directory(
      p.join(runtimeDirectory.path, 'instances'),
    );
    await instancesDirectory
        .create(recursive: true)
        .timeout(_fileOperationTimeout);

    final takeoverHandle = await File(
      p.join(runtimeDirectory.path, 'instance-takeover.lock'),
    ).open(mode: FileMode.append).timeout(_fileOperationTimeout);
    var takeoverLocked = false;
    try {
      final stopwatch = Stopwatch()..start();
      while (!takeoverLocked) {
        try {
          takeoverHandle.lockSync();
          takeoverLocked = true;
        } on FileSystemException catch (error) {
          if (!_isLockContention(error) ||
              stopwatch.elapsed >= _takeoverLockTimeout) {
            throw const OpenHandSingleInstanceException(
              '无法取得 OpenHand 单实例接管锁。',
            );
          }
          await Future<void>.delayed(_takeoverRetryDelay);
        }
      }
      stopwatch.stop();

      final running = await _loadRunningProcesses();
      final currentExecutable = _normalizeExecutable(
        Platform.resolvedExecutable,
      );
      final targets = <int, String>{};
      for (final process in running.values) {
        if (process.pid != pid &&
            await _belongsToCurrentApplication(
              process.executable,
              currentExecutable,
            )) {
          targets[process.pid] = process.executable;
        }
      }

      final recordFiles = await _listInstanceRecords(instancesDirectory);
      for (final file in recordFiles) {
        final record = await _readInstanceRecord(file);
        if (record == null || record.pid == pid) {
          await _deleteFileQuietly(file);
          continue;
        }
        final live = running[record.pid];
        if (live == null ||
            !_sameExecutable(live.executable, record.executable)) {
          await _deleteFileQuietly(file);
          continue;
        }
        targets[record.pid] = live.executable;
      }

      if (targets.isNotEmpty) {
        final ownedProcesses = <int, String>{...targets};
        _collectDescendants(running, targets.keys, ownedProcesses);
        await _terminatePreviousInstances(targets, ownedProcesses);
      }

      for (final file in recordFiles) {
        await _deleteFileQuietly(file);
      }
      await _pruneTemporaryRecords(instancesDirectory);

      final token = _newToken();
      final recordFile = File(
        p.join(
          instancesDirectory.path,
          '$_recordPrefix$pid-$token$_recordSuffix',
        ),
      );
      await _writeInstanceRecord(
        recordFile,
        _InstanceRecord(pid: pid, token: token, executable: currentExecutable),
      );
      return OpenHandSingleInstance._(recordFile, token);
    } finally {
      if (takeoverLocked) {
        try {
          takeoverHandle.unlockSync();
        } catch (error, stack) {
          silentLog('single_instance', '释放单实例接管锁', error, stack);
        }
      }
      try {
        await takeoverHandle.close().timeout(_fileOperationTimeout);
      } catch (error, stack) {
        silentLog('single_instance', '关闭单实例接管锁文件', error, stack);
      }
    }
  }

  /// 仅删除属于当前进程令牌的登记，避免覆盖正在接管的新实例。
  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    final recordFile = _recordFile;
    if (recordFile == null) return;
    final record = await _readInstanceRecord(recordFile);
    if (record?.pid == pid && record?.token == _token) {
      await _deleteFileQuietly(recordFile);
    }
  }

  static Future<void> _terminatePreviousInstances(
    Map<int, String> roots,
    Map<int, String> ownedProcesses,
  ) async {
    var remainingRoots = await _matchingProcesses(roots);
    _signalProcesses(remainingRoots.keys, ProcessSignal.sigterm, '请求旧实例退出');
    remainingRoots = await _waitForMatchingProcesses(
      remainingRoots,
      _gracefulExitTimeout,
    );
    if (remainingRoots.isNotEmpty) {
      final remainingOwned = await _matchingProcesses(ownedProcesses);
      _signalProcesses(
        remainingOwned.keys.toList(growable: false).reversed,
        ProcessSignal.sigterm,
        '终止旧实例残留进程',
      );
      remainingRoots = await _waitForMatchingProcesses(
        remainingRoots,
        _residualExitTimeout,
      );
    }

    final residualProcesses = await _matchingProcesses(ownedProcesses);
    if (residualProcesses.isNotEmpty) {
      _signalProcesses(
        residualProcesses.keys.toList(growable: false).reversed,
        ProcessSignal.sigkill,
        '强制终止旧实例残留进程',
      );
      final survivors = await _waitForMatchingProcesses(
        residualProcesses,
        _forcedExitTimeout,
      );
      if (survivors.isNotEmpty) {
        throw OpenHandSingleInstanceException(
          '无法终止旧 OpenHand 进程：${survivors.keys.join(', ')}。',
        );
      }
    }
  }

  static void _signalProcesses(
    Iterable<int> processIds,
    ProcessSignal signal,
    String action,
  ) {
    for (final processId in processIds) {
      if (processId <= 0 || processId == pid) continue;
      try {
        Process.killPid(processId, signal);
      } catch (error, stack) {
        silentLog('single_instance', '$action：PID $processId', error, stack);
      }
    }
  }

  static Future<Map<int, String>> _matchingProcesses(
    Map<int, String> expected,
  ) async {
    if (expected.isEmpty) return const <int, String>{};
    final running = await _loadRunningProcesses();
    return <int, String>{
      for (final entry in expected.entries)
        if (running[entry.key] case final live?
            when _sameExecutable(live.executable, entry.value))
          entry.key: entry.value,
    };
  }

  static Future<Map<int, String>> _waitForMatchingProcesses(
    Map<int, String> expected,
    Duration timeout,
  ) async {
    var remaining = await _matchingProcesses(expected);
    if (remaining.isEmpty || timeout <= Duration.zero) return remaining;
    final stopwatch = Stopwatch()..start();
    var delay = _processPollMinDelay;
    while (remaining.isNotEmpty && stopwatch.elapsed < timeout) {
      final available = timeout - stopwatch.elapsed;
      await Future<void>.delayed(delay < available ? delay : available);
      remaining = await _matchingProcesses(remaining);
      final doubled = delay * 2;
      delay = doubled < _processPollMaxDelay ? doubled : _processPollMaxDelay;
    }
    stopwatch.stop();
    return remaining;
  }

  static void _collectDescendants(
    Map<int, _RunningProcess> running,
    Iterable<int> rootIds,
    Map<int, String> output,
  ) {
    var frontier = rootIds.toSet();
    while (frontier.isNotEmpty && output.length < _maxTrackedDescendants) {
      final next = <int>{};
      for (final process in running.values) {
        if (process.pid == pid ||
            output.containsKey(process.pid) ||
            !frontier.contains(process.parentPid)) {
          continue;
        }
        output[process.pid] = process.executable;
        next.add(process.pid);
        if (output.length >= _maxTrackedDescendants) break;
      }
      frontier = next;
    }
  }

  static Future<Map<int, _RunningProcess>> _loadRunningProcesses() async {
    if (Platform.isLinux) return _loadLinuxProcesses();
    if (Platform.isWindows) return _loadWindowsProcesses();

    final result = await runProcessWithTimeout(
      '/bin/ps',
      const <String>['-axo', 'pid=,ppid=,comm='],
      timeout: _processQueryTimeout,
      maxStdoutBytes: _maxProcessListBytes,
      maxStderrBytes: 64 * kBytesPerKiB,
      startInNewProcessGroup: false,
      tag: 'single_instance.ps',
    );
    if (result == null || result.exitCode != 0) {
      throw const OpenHandSingleInstanceException('无法读取系统进程列表。');
    }
    final processes = <int, _RunningProcess>{};
    final linePattern = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.+?)\s*$');
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      final match = linePattern.firstMatch(line);
      if (match == null) continue;
      final processId = int.tryParse(match.group(1)!);
      final parentId = int.tryParse(match.group(2)!);
      final executable = _normalizeExecutable(match.group(3)!);
      if (processId == null || parentId == null || executable.isEmpty) continue;
      processes[processId] = _RunningProcess(
        pid: processId,
        parentPid: parentId,
        executable: executable,
      );
    }
    return processes;
  }

  static Future<Map<int, _RunningProcess>> _loadLinuxProcesses() async {
    final processes = <int, _RunningProcess>{};
    final entities = await Directory('/proc')
        .list(followLinks: false)
        .take(65536)
        .toList()
        .timeout(_processQueryTimeout);
    for (final entity in entities) {
      final processId = int.tryParse(p.basename(entity.path));
      if (processId == null || processId <= 0) continue;
      try {
        final executable = _normalizeExecutable(
          await Link(
            p.join(entity.path, 'exe'),
          ).resolveSymbolicLinks().timeout(_fileOperationTimeout),
        );
        final statParts = await File(
          p.join(entity.path, 'stat'),
        ).readAsString().timeout(_fileOperationTimeout);
        final commandEnd = statParts.lastIndexOf(')');
        if (commandEnd < 0) continue;
        final tail = statParts.substring(commandEnd + 1).trim().split(' ');
        final parentId = tail.length > 1 ? int.tryParse(tail[1]) : null;
        if (parentId == null || executable.isEmpty) continue;
        processes[processId] = _RunningProcess(
          pid: processId,
          parentPid: parentId,
          executable: executable,
        );
      } on FileSystemException {
        // 进程可能已退出或属于不可读取的其他用户。
      } on TimeoutException {
        // 单个 /proc 条目读取超时不阻塞完整进程快照。
      }
    }
    return processes;
  }

  static Future<Map<int, _RunningProcess>> _loadWindowsProcesses() async {
    const script = r'''
$ErrorActionPreference = 'Stop'
Get-CimInstance Win32_Process | ForEach-Object {
  if ($_.ExecutablePath) {
    "{0}`t{1}`t{2}" -f $_.ProcessId, $_.ParentProcessId, $_.ExecutablePath
  }
}
''';
    ProcessResult? result;
    for (final executable in const <String>['powershell.exe', 'pwsh.exe']) {
      result = await runProcessWithTimeout(
        executable,
        const <String>['-NoProfile', '-NonInteractive', '-Command', script],
        timeout: _processQueryTimeout,
        maxStdoutBytes: _maxProcessListBytes,
        maxStderrBytes: 64 * kBytesPerKiB,
        startInNewProcessGroup: false,
        tag: 'single_instance.windows_processes',
      );
      if (result != null && result.exitCode == 0) break;
    }
    if (result == null || result.exitCode != 0) {
      throw const OpenHandSingleInstanceException('无法读取 Windows 进程列表。');
    }
    final processes = <int, _RunningProcess>{};
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      final processId = int.tryParse(parts[0].trim());
      final parentId = int.tryParse(parts[1].trim());
      final executable = _normalizeExecutable(parts.sublist(2).join('\t'));
      if (processId == null || parentId == null || executable.isEmpty) continue;
      processes[processId] = _RunningProcess(
        pid: processId,
        parentPid: parentId,
        executable: executable,
      );
    }
    return processes;
  }

  static Future<List<File>> _listInstanceRecords(Directory directory) async {
    final entities = await directory
        .list(followLinks: false)
        .where(
          (entity) =>
              entity is File &&
              p.basename(entity.path).startsWith(_recordPrefix) &&
              p.basename(entity.path).endsWith(_recordSuffix),
        )
        .take(_maxInstanceRecords + 1)
        .toList()
        .timeout(_fileOperationTimeout);
    if (entities.length > _maxInstanceRecords) {
      throw const OpenHandSingleInstanceException('OpenHand 实例登记数量异常。');
    }
    return entities.cast<File>();
  }

  static Future<_InstanceRecord?> _readInstanceRecord(File file) async {
    try {
      final stat = await file.stat().timeout(_fileOperationTimeout);
      if (stat.type != FileSystemEntityType.file || stat.size > 4096) {
        return null;
      }
      final decoded = jsonDecode(
        await file.readAsString().timeout(_fileOperationTimeout),
      );
      if (decoded is! Map) return null;
      final record = _InstanceRecord.fromJson(decoded.cast<String, Object?>());
      return record.applicationId == _applicationId &&
              record.version == _recordVersion
          ? record
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeInstanceRecord(
    File target,
    _InstanceRecord record,
  ) async {
    final temporary = File('${target.path}$_temporaryRecordSuffix');
    try {
      await temporary
          .writeAsString(jsonEncode(record.toJson()), flush: true)
          .timeout(_fileOperationTimeout);
      await temporary.rename(target.path).timeout(_fileOperationTimeout);
    } catch (error, stack) {
      await _deleteFileQuietly(temporary);
      silentLog('single_instance', '写入当前实例登记', error, stack);
      throw const OpenHandSingleInstanceException('无法写入 OpenHand 实例登记。');
    }
  }

  static Future<void> _pruneTemporaryRecords(Directory directory) async {
    try {
      final entities = await directory
          .list(followLinks: false)
          .take(_maxInstanceRecords)
          .toList()
          .timeout(_fileOperationTimeout);
      for (final entity in entities) {
        if (entity is File &&
            p.basename(entity.path).startsWith(_recordPrefix) &&
            p.basename(entity.path).endsWith(_temporaryRecordSuffix)) {
          await _deleteFileQuietly(entity);
        }
      }
    } catch (error, stack) {
      silentLog('single_instance', '清理实例临时登记', error, stack);
    }
  }

  static Future<void> _deleteFileQuietly(File file) async {
    try {
      if (await file.exists().timeout(_fileOperationTimeout)) {
        await file.delete().timeout(_fileOperationTimeout);
      }
    } catch (error, stack) {
      silentLog('single_instance', '删除实例登记 ${file.path}', error, stack);
    }
  }

  static bool _isLockContention(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (Platform.isWindows) return code == 33 || code == 36;
    return code == 11 || code == 13 || code == 35;
  }

  static String _normalizeExecutable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '' : p.normalize(p.absolute(trimmed));
  }

  static bool _sameExecutable(String left, String right) {
    if (left.isEmpty || right.isEmpty) return false;
    return Platform.isWindows
        ? left.toLowerCase() == right.toLowerCase()
        : p.equals(left, right);
  }

  static Future<bool> _belongsToCurrentApplication(
    String executable,
    String currentExecutable,
  ) async {
    if (_sameExecutable(executable, currentExecutable)) return true;
    if (!Platform.isMacOS ||
        p.basename(executable) != p.basename(currentExecutable)) {
      return false;
    }
    final macOsDirectory = p.dirname(executable);
    final contentsDirectory = p.dirname(macOsDirectory);
    if (p.basename(macOsDirectory) != 'MacOS' ||
        p.basename(contentsDirectory) != 'Contents' ||
        !p.basename(p.dirname(contentsDirectory)).endsWith('.app')) {
      return false;
    }
    try {
      final infoPlist = File(p.join(contentsDirectory, 'Info.plist'));
      final stat = await infoPlist.stat().timeout(_fileOperationTimeout);
      if (stat.type != FileSystemEntityType.file ||
          stat.size <= 0 ||
          stat.size > _maxMacInfoPlistBytes) {
        return false;
      }
      final contents = utf8.decode(
        await infoPlist.readAsBytes().timeout(_fileOperationTimeout),
        allowMalformed: true,
      );
      return contents.contains('CFBundleIdentifier') &&
          contents.contains(_applicationId);
    } catch (_) {
      return false;
    }
  }

  static String _newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

final class _RunningProcess {
  const _RunningProcess({
    required this.pid,
    required this.parentPid,
    required this.executable,
  });

  final int pid;
  final int parentPid;
  final String executable;
}

final class _InstanceRecord {
  const _InstanceRecord({
    required this.pid,
    required this.token,
    required this.executable,
    this.applicationId = OpenHandSingleInstance._applicationId,
    this.version = OpenHandSingleInstance._recordVersion,
  });

  factory _InstanceRecord.fromJson(Map<String, Object?> json) {
    return _InstanceRecord(
      pid: json['pid'] is int ? json['pid']! as int : -1,
      token: json['token'] is String ? json['token']! as String : '',
      executable: json['executable'] is String
          ? OpenHandSingleInstance._normalizeExecutable(
              json['executable']! as String,
            )
          : '',
      applicationId: json['application_id'] is String
          ? json['application_id']! as String
          : '',
      version: json['version'] is int ? json['version']! as int : -1,
    );
  }

  final int pid;
  final String token;
  final String executable;
  final String applicationId;
  final int version;

  Map<String, Object> toJson() => <String, Object>{
    'version': version,
    'application_id': applicationId,
    'pid': pid,
    'token': token,
    'executable': executable,
    'started_at': DateTime.now().toUtc().toIso8601String(),
  };
}
