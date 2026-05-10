import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../model/mcp_server.dart';
import 'mcp_tool_discovery_service.dart';

/// STDIO MCP 服务进程的运行状态。
enum StdioProcessState { stopped, starting, running, stopping }

/// 单个 STDIO MCP 服务进程的运行时信息快照。
class StdioProcessInfo {
  const StdioProcessInfo({
    this.state = StdioProcessState.stopped,
    this.pid,
    this.startedAt,
    this.memoryBytes,
    this.logs = const <String>[],
    this.errorMessage,
  });

  final StdioProcessState state;
  final int? pid;
  final DateTime? startedAt;
  final int? memoryBytes;
  final List<String> logs;
  final String? errorMessage;

  bool get isRunning => state == StdioProcessState.running;
  bool get isStopped => state == StdioProcessState.stopped;
  bool get isTransitioning =>
      state == StdioProcessState.starting ||
      state == StdioProcessState.stopping;

  Duration? get uptime {
    if (startedAt == null || !isRunning) return null;
    return DateTime.now().toUtc().difference(startedAt!);
  }

  StdioProcessInfo copyWith({
    StdioProcessState? state,
    int? pid,
    bool clearPid = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
    int? memoryBytes,
    bool clearMemoryBytes = false,
    List<String>? logs,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return StdioProcessInfo(
      state: state ?? this.state,
      pid: clearPid ? null : pid ?? this.pid,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      memoryBytes: clearMemoryBytes ? null : memoryBytes ?? this.memoryBytes,
      logs: logs ?? this.logs,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

/// 管理 STDIO 类型 MCP 服务的进程生命周期。
///
/// 每个 STDIO MCP 服务可以独立启动/停止，进程日志实时收集，
/// 应用退出时自动终止所有子进程。
class McpStdioProcessManager extends ChangeNotifier {
  McpStdioProcessManager._();

  static final McpStdioProcessManager instance = McpStdioProcessManager._();

  static const int _maxLogLines = 2000;

  final Map<String, _ManagedProcess> _processes = {};

  /// 获取指定服务的进程信息。
  StdioProcessInfo infoFor(String serverName) {
    return _processes[serverName]?.info ?? const StdioProcessInfo();
  }

  /// 获取所有正在运行的服务名列表。
  List<String> get runningServers => _processes.entries
      .where((e) => e.value.info.isRunning)
      .map((e) => e.key)
      .toList(growable: false);

  /// 启动指定 STDIO MCP 服务进程。
  Future<void> startServer(McpServer server) async {
    if (server.type != McpServerType.stdio) return;
    final name = server.name;

    final existing = _processes[name];
    if (existing != null && !existing.info.isStopped) return;

    _processes[name] = _ManagedProcess(
      info: const StdioProcessInfo(state: StdioProcessState.starting),
    );
    notifyListeners();

    try {
      final resolved = await _resolveStdioLaunch(server);
      final process = await Process.start(
        resolved.executable,
        resolved.args,
        environment: resolved.environment,
        runInShell: Platform.isWindows,
      );

      final logs = <String>[];
      logs.add('[${_timestamp()}] 进程已启动 (PID: ${process.pid})');
      logs.add('[${_timestamp()}] 命令: ${resolved.executable} ${resolved.args.join(' ')}');
      logs.add('');

      final managed = _ManagedProcess(
        info: StdioProcessInfo(
          state: StdioProcessState.running,
          pid: process.pid,
          startedAt: DateTime.now().toUtc(),
          logs: List.unmodifiable(logs),
        ),
        process: process,
      );
      _processes[name] = managed;
      notifyListeners();

      // 监听 stdout
      process.stdout.transform(utf8.decoder).listen(
        (data) => _appendLog(name, data, isStderr: false),
        onError: (e) => _appendLog(name, '[stdout error] $e', isStderr: true),
        onDone: () => _appendLog(name, '[stdout closed]', isStderr: false),
      );

      // 监听 stderr
      process.stderr.transform(utf8.decoder).listen(
        (data) => _appendLog(name, data, isStderr: true),
        onError: (e) => _appendLog(name, '[stderr error] $e', isStderr: true),
        onDone: () => _appendLog(name, '[stderr closed]', isStderr: false),
      );

      // 监听进程退出
      unawaited(process.exitCode.then((code) {
        _appendLog(name, '\n[${_timestamp()}] 进程已退出 (exit code: $code)', isStderr: false);
        final current = _processes[name];
        if (current != null) {
          _processes[name] = _ManagedProcess(
            info: current.info.copyWith(
              state: StdioProcessState.stopped,
              clearPid: true,
            ),
          );
          notifyListeners();
        }
      }));

      // 进程已启动，标记就绪
      _logProcessReady(name);
    } catch (e) {
      _processes[name] = _ManagedProcess(
        info: StdioProcessInfo(
          state: StdioProcessState.stopped,
          errorMessage: '$e',
          logs: ['[${_timestamp()}] 启动失败: $e'],
        ),
      );
      notifyListeners();
    }
  }

  /// 停止指定 STDIO MCP 服务进程。
  Future<void> stopServer(String serverName) async {
    final managed = _processes[serverName];
    if (managed == null || managed.process == null) return;
    if (managed.info.state == StdioProcessState.stopping) return;

    _processes[serverName] = _ManagedProcess(
      info: managed.info.copyWith(state: StdioProcessState.stopping),
      process: managed.process,
    );
    notifyListeners();

    _appendLog(serverName, '\n[${_timestamp()}] 正在停止进程…', isStderr: false);

    try {
      // 先尝试优雅关闭 stdin
      try {
        managed.process!.stdin.close();
      } catch (_) {}

      // 等待进程退出
      final exited = await managed.process!.exitCode
          .timeout(const Duration(seconds: 3))
          .then((_) => true)
          .catchError((_) => false);

      if (!exited) {
        managed.process!.kill();
        await managed.process!.exitCode
            .timeout(const Duration(seconds: 2))
            .catchError((_) {
          if (!Platform.isWindows) {
            managed.process!.kill(ProcessSignal.sigkill);
          }
          return -1;
        });
      }
    } catch (e) {
      _appendLog(serverName, '[${_timestamp()}] 停止异常: $e', isStderr: true);
    }

    final current = _processes[serverName];
    if (current != null && current.info.state != StdioProcessState.stopped) {
      _processes[serverName] = _ManagedProcess(
        info: current.info.copyWith(
          state: StdioProcessState.stopped,
          clearPid: true,
        ),
      );
      notifyListeners();
    }
  }

  /// 停止所有正在运行的进程（应用退出时调用）。
  Future<void> stopAll() async {
    final names = runningServers;
    await Future.wait(names.map(stopServer));
  }

  /// 清除指定服务的日志。
  void clearLogs(String serverName) {
    final managed = _processes[serverName];
    if (managed == null) return;
    _processes[serverName] = _ManagedProcess(
      info: managed.info.copyWith(logs: const []),
      process: managed.process,
    );
    notifyListeners();
  }

  void _appendLog(String serverName, String data, {required bool isStderr}) {
    final managed = _processes[serverName];
    if (managed == null) return;

    final lines = data.split('\n');
    final currentLogs = List<String>.from(managed.info.logs);
    for (final line in lines) {
      if (line.trim().isEmpty && currentLogs.isNotEmpty && currentLogs.last.isEmpty) {
        continue; // 避免连续空行
      }
      currentLogs.add(isStderr ? '[stderr] $line' : line);
    }

    // 限制日志行数
    while (currentLogs.length > _maxLogLines) {
      currentLogs.removeAt(0);
    }

    _processes[serverName] = _ManagedProcess(
      info: managed.info.copyWith(logs: List.unmodifiable(currentLogs)),
      process: managed.process,
    );
    notifyListeners();
  }

  /// STDIO MCP 服务启动后即处于就绪状态，等待外部通过 stdin 发送 MCP 协议请求。
  /// 进程管理器不负责 MCP 协议握手——那是 discovery service 的职责。
  void _logProcessReady(String serverName) {
    _appendLog(serverName, '[${_timestamp()}] 服务就绪，等待 MCP 协议连接…', isStderr: false);
  }

  /// 获取进程的运行时环境信息。
  Future<Map<String, String>> getRuntimeInfo(String serverName) async {
    final managed = _processes[serverName];
    final info = <String, String>{};

    info['状态'] = switch (managed?.info.state ?? StdioProcessState.stopped) {
      StdioProcessState.stopped => '已停止',
      StdioProcessState.starting => '启动中',
      StdioProcessState.running => '运行中',
      StdioProcessState.stopping => '停止中',
    };

    if (managed?.info.pid != null) {
      info['PID'] = '${managed!.info.pid}';
    }

    if (managed?.info.startedAt != null) {
      final uptime = managed!.info.uptime;
      if (uptime != null) {
        info['运行时长'] = _formatDuration(uptime);
      }
      info['启动时间'] = managed.info.startedAt!.toLocal().toString().split('.').first;
    }

    info['操作系统'] = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    info['处理器数'] = '${Platform.numberOfProcessors}';
    info['Dart 版本'] = Platform.version.split(' ').first;

    // 尝试获取进程内存信息（macOS/Linux）
    if (managed?.info.pid != null && !Platform.isWindows) {
      try {
        final result = await Process.run(
          'ps', ['-o', 'rss=', '-p', '${managed!.info.pid}'],
        ).timeout(const Duration(seconds: 3));
        if (result.exitCode == 0) {
          final rssKb = int.tryParse(result.stdout.toString().trim());
          if (rssKb != null) {
            info['内存 (RSS)'] = _formatBytes(rssKb * 1024);
          }
        }
      } catch (_) {}

      // 获取线程数
      try {
        final result = await Process.run(
          'ps', ['-M', '-p', '${managed!.info.pid}'],
        ).timeout(const Duration(seconds: 3));
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().trim().split('\n');
          info['线程数'] = '${lines.length - 1}'; // 减去 header 行
        }
      } catch (_) {}
    }

    // 隔离缓存目录信息
    final cacheRoot = mcpStdioIsolatedCacheRoot();
    final cacheDir = Directory(cacheRoot);
    info['隔离缓存'] = cacheDir.existsSync() ? cacheRoot : '(未创建)';
    if (cacheDir.existsSync()) {
      try {
        int totalSize = 0;
        int fileCount = 0;
        await for (final entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
            fileCount++;
          }
        }
        info['缓存大小'] = _formatBytes(totalSize);
        info['缓存文件数'] = '$fileCount';
      } catch (_) {}
    }

    return info;
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  static String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}天 ${d.inHours % 24}时 ${d.inMinutes % 60}分';
    if (d.inHours > 0) return '${d.inHours}时 ${d.inMinutes % 60}分 ${d.inSeconds % 60}秒';
    if (d.inMinutes > 0) return '${d.inMinutes}分 ${d.inSeconds % 60}秒';
    return '${d.inSeconds}秒';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  void dispose() {
    stopAll();
    super.dispose();
  }
}

class _ManagedProcess {
  const _ManagedProcess({required this.info, this.process});

  final StdioProcessInfo info;
  final Process? process;
}

/// 解析 STDIO MCP 服务的启动参数（复用 discovery service 的逻辑）。
Future<_ResolvedLaunch> _resolveStdioLaunch(McpServer server) async {
  final separator = Platform.isWindows ? ';' : ':';
  final originalPath = Platform.environment['PATH'] ?? '';
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  final extraSegments = <String>[];
  if (Platform.isMacOS) {
    extraSegments.addAll(const [
      '/opt/homebrew/bin',
      '/opt/homebrew/sbin',
      '/usr/local/bin',
      '/usr/local/sbin',
    ]);
  } else if (Platform.isLinux) {
    extraSegments.addAll(const ['/usr/local/bin', '/usr/local/sbin', '/snap/bin']);
  }
  if (home != null && home.isNotEmpty) {
    if (Platform.isWindows) {
      extraSegments.addAll([
        '$home\\AppData\\Roaming\\npm',
        '$home\\.cargo\\bin',
        '$home\\.bun\\bin',
        '$home\\.deno\\bin',
        '$home\\.local\\bin',
      ]);
    } else {
      extraSegments.addAll([
        '$home/.npm-global/bin',
        '$home/.local/bin',
        '$home/.cargo/bin',
        '$home/.bun/bin',
        '$home/.deno/bin',
        '$home/.volta/bin',
      ]);
    }
  }

  // 登录 shell PATH 探测
  if (!Platform.isWindows) {
    final shellPath = await _probeLoginShellPathForManager();
    if (shellPath.isNotEmpty) {
      final shellSegments = shellPath.split(separator).map((s) => s.trim()).where((s) => s.isNotEmpty);
      extraSegments.insertAll(0, shellSegments.toList());
    }
  }

  final mergedSegments = <String>[];
  final seen = <String>{};
  final originalSegments = originalPath.split(separator).map((s) => s.trim()).where((s) => s.isNotEmpty);
  for (final segment in [...extraSegments, ...originalSegments]) {
    if (seen.add(segment)) mergedSegments.add(segment);
  }
  final mergedPath = mergedSegments.join(separator);

  // 解析命令
  final rawCommand = server.command.trim();
  final tokens = _tokenizeCommand(rawCommand);
  final command = tokens.isNotEmpty ? tokens.first : rawCommand;
  final inlineArgs = tokens.length > 1 ? tokens.sublist(1) : const <String>[];
  final args = [...inlineArgs, ...server.args];

  // 查找可执行文件绝对路径
  String executable = command;
  if (command.isNotEmpty && !command.contains('/') && !(Platform.isWindows && command.contains('\\'))) {
    for (final dir in mergedSegments) {
      final full = p.join(dir, command);
      if (FileSystemEntity.typeSync(full) == FileSystemEntityType.file) {
        executable = full;
        break;
      }
      if (Platform.isWindows) {
        for (final ext in ['.cmd', '.bat', '.exe', '.ps1']) {
          final withExt = '$full$ext';
          if (FileSystemEntity.typeSync(withExt) == FileSystemEntityType.file) {
            executable = withExt;
            break;
          }
        }
        if (executable != command) break;
      }
    }
  }

  // 构建环境变量
  final env = Map<String, String>.from(Platform.environment);
  env['PATH'] = mergedPath;

  // 注入隔离缓存（复用 discovery service 的逻辑，确保目录已创建且路径一致）
  env.addAll(mcpStdioIsolatedCacheEnv());

  return _ResolvedLaunch(executable: executable, args: args, environment: env);
}

class _ResolvedLaunch {
  const _ResolvedLaunch({
    required this.executable,
    required this.args,
    required this.environment,
  });

  final String executable;
  final List<String> args;
  final Map<String, String> environment;
}

/// 简化版 shell 命令拆词。
List<String> _tokenizeCommand(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return const [];
  if (!trimmed.contains(RegExp(r'\s'))) return [trimmed];
  final tokens = <String>[];
  final buffer = StringBuffer();
  bool inSingle = false;
  bool inDouble = false;
  bool hasContent = false;
  for (int i = 0; i < trimmed.length; i++) {
    final ch = trimmed[i];
    if (!inSingle && !inDouble && ch == '\\' && i + 1 < trimmed.length) {
      buffer.write(trimmed[i + 1]);
      i++;
      hasContent = true;
      continue;
    }
    if (!inDouble && ch == "'") { inSingle = !inSingle; hasContent = true; continue; }
    if (!inSingle && ch == '"') { inDouble = !inDouble; hasContent = true; continue; }
    if (!inSingle && !inDouble && (ch == ' ' || ch == '\t')) {
      if (hasContent) { tokens.add(buffer.toString()); buffer.clear(); hasContent = false; }
      continue;
    }
    buffer.write(ch);
    hasContent = true;
  }
  if (inSingle || inDouble) return [trimmed];
  if (hasContent) tokens.add(buffer.toString());
  return tokens.isEmpty ? [trimmed] : tokens;
}

String? _cachedShellPath;

Future<String> _probeLoginShellPathForManager() async {
  if (_cachedShellPath != null) return _cachedShellPath!;
  try {
    final shell = Platform.environment['SHELL']?.trim();
    if (shell == null || shell.isEmpty) return '';
    final result = await Process.run(
      shell, ['-l', '-c', 'echo \$PATH'],
    ).timeout(const Duration(seconds: 5));
    if (result.exitCode == 0) {
      _cachedShellPath = result.stdout.toString().trim();
      return _cachedShellPath!;
    }
  } catch (_) {}
  _cachedShellPath = '';
  return '';
}
