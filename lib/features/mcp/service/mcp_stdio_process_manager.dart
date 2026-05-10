import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
      // 解析实际的可执行文件和参数。对于 npx 命令，尝试直接定位已安装包的
      // 入口脚本用 node 执行，避免 npx 的启动开销和 stdin 转发问题。
      final launch = await _resolveDirectLaunch(server);
      final process = await Process.start(
        launch.executable,
        launch.args,
        environment: launch.environment,
      );

      final logs = <String>[];
      logs.add('[${_timestamp()}] 进程已启动 (PID: ${process.pid})');
      logs.add('[${_timestamp()}] 命令: ${launch.executable} ${launch.args.join(' ')}');
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

      // 监听 stdout - 同时用于日志和握手响应检测
      final handshakeCompleter = Completer<bool>();
      process.stdout.transform(utf8.decoder).listen(
        (data) {
          _appendLog(name, data, isStderr: false);
          // 检测 MCP initialize 响应
          if (!handshakeCompleter.isCompleted &&
              (data.contains('"result"') || data.contains('"protocolVersion"'))) {
            handshakeCompleter.complete(true);
          }
        },
        onError: (e) => _appendLog(name, '[stdout error] $e', isStderr: true),
        onDone: () {
          _appendLog(name, '[stdout closed]', isStderr: false);
          if (!handshakeCompleter.isCompleted) handshakeCompleter.complete(false);
        },
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
        if (!handshakeCompleter.isCompleted) handshakeCompleter.complete(false);
      }));

      // 启动后自动执行 MCP 协议握手
      unawaited(_initializeMcpProtocol(name, process, handshakeCompleter));
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

  /// 启动后自动通过 stdin 发送 MCP initialize 请求完成协议握手。
  Future<void> _initializeMcpProtocol(
    String serverName,
    Process process,
    Completer<bool> responseCompleter,
  ) async {
    _appendLog(serverName, '[${_timestamp()}] MCP 协议握手中…', isStderr: false);
    try {
      // 等待 npx 解析并启动实际的 MCP 服务进程（首次可能需要下载包）
      await Future.delayed(const Duration(seconds: 2));
      final managed = _processes[serverName];
      if (managed == null || !managed.info.isRunning) return;

      // 构造 MCP initialize 请求（JSON-RPC 2.0）
      final initRequest = jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-11-25',
          'capabilities': {},
          'clientInfo': {'name': 'OpenHand', 'version': '1.0.0'},
        },
      });
      final body = utf8.encode(initRequest);
      final header = 'Content-Length: ${body.length}\r\n\r\n';

      // 发送 initialize 请求（尾部追加 \n 兼容 bare JSON-line 模式的 MCP 服务）
      process.stdin.add(utf8.encode(header));
      process.stdin.add(body);
      process.stdin.add(utf8.encode('\n'));
      await process.stdin.flush();

      // 等待 stdout 中出现响应（最多 90 秒，npx 首次运行需要下载包）
      final gotResponse = await responseCompleter.future
          .timeout(const Duration(seconds: 90), onTimeout: () => false);

      if (gotResponse) {
        _appendLog(serverName, '[${_timestamp()}] ✓ MCP 握手成功', isStderr: false);

        // 发送 initialized 通知
        final notification = jsonEncode({
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        });
        final notifBody = utf8.encode(notification);
        final notifHeader = 'Content-Length: ${notifBody.length}\r\n\r\n';
        process.stdin.add(utf8.encode(notifHeader));
        process.stdin.add(notifBody);
        process.stdin.add(utf8.encode('\n'));
        await process.stdin.flush();
        _appendLog(serverName, '[${_timestamp()}] ✓ 服务已就绪，可正常使用', isStderr: false);
      } else {
        _appendLog(serverName, '[${_timestamp()}] ⚠ 握手超时或进程已退出', isStderr: false);
      }
    } catch (e) {
      _appendLog(serverName, '[${_timestamp()}] ⚠ 握手异常: $e', isStderr: false);
    }
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

class _DirectLaunch {
  const _DirectLaunch({required this.executable, required this.args, this.environment});
  final String executable;
  final List<String> args;
  final Map<String, String>? environment;
}

/// 解析 STDIO MCP 服务的直接启动参数。
/// 对于 npx 命令，尝试定位已全局安装的包入口脚本，直接用 node 执行。
/// 这避免了 npx 的启动开销、下载延迟、以及 login shell stdin 转发问题。
Future<_DirectLaunch> _resolveDirectLaunch(McpServer server) async {
  final command = server.command.trim();
  final isNpx = command == 'npx' || command.endsWith('/npx');

  if (isNpx && server.args.isNotEmpty) {
    final packageName = server.args.first.trim();
    final extraArgs = server.args.length > 1 ? server.args.sublist(1) : const <String>[];

    // 尝试通过 login shell 定位已安装包的实际路径
    final resolved = await _resolveNpxPackagePath(packageName);
    if (resolved != null) {
      return _DirectLaunch(
        executable: resolved.nodeBin,
        args: [resolved.entryScript, ...extraArgs],
      );
    }
  }

  // 回退：通过 login shell 执行原始命令
  final shell = _pickShellForLaunch();
  final cmdLine = [command, ...server.args].map((p) => p.contains(' ') ? "'$p'" : p).join(' ');
  // 使用 exec 替换 shell 进程，确保 stdin 直接连接到目标进程
  return _DirectLaunch(
    executable: shell,
    args: ['-l', '-c', 'exec $cmdLine'],
  );
}

class _ResolvedNpxPackage {
  const _ResolvedNpxPackage({required this.nodeBin, required this.entryScript});
  final String nodeBin;
  final String entryScript;
}

/// 通过 login shell 定位 npx 包的实际安装路径和入口脚本。
Future<_ResolvedNpxPackage?> _resolveNpxPackagePath(String packageName) async {
  try {
    final shell = _pickShellForLaunch();
    // 获取 node 和全局 node_modules 路径
    final result = await Process.run(
      shell, ['-l', '-c', 'echo \$(which node);\$(npm root -g)'],
    ).timeout(const Duration(seconds: 8));
    if (result.exitCode != 0) return null;

    final lines = result.stdout.toString().trim().split('\n');
    if (lines.length < 2) return null;
    final nodeBin = lines[0].trim();
    final globalRoot = lines[1].trim();
    if (nodeBin.isEmpty || globalRoot.isEmpty) return null;
    if (!File(nodeBin).existsSync()) return null;

    // 解析包名（处理 @scope/name@version 格式）
    final cleanName = packageName.replaceAll(RegExp(r'@[^/]*$'), ''); // 移除 @version
    final packageDir = '$globalRoot/$cleanName';
    if (!Directory(packageDir).existsSync()) return null;

    // 从 package.json 读取 bin 入口
    final pkgJsonFile = File('$packageDir/package.json');
    if (!pkgJsonFile.existsSync()) return null;
    final pkgJson = jsonDecode(pkgJsonFile.readAsStringSync());
    final bin = pkgJson['bin'];
    String? entryScript;
    if (bin is String) {
      entryScript = '$packageDir/$bin';
    } else if (bin is Map) {
      // 取第一个 bin 入口
      final firstBin = bin.values.first;
      if (firstBin is String) entryScript = '$packageDir/$firstBin';
    }
    if (entryScript == null || !File(entryScript).existsSync()) return null;

    return _ResolvedNpxPackage(nodeBin: nodeBin, entryScript: entryScript);
  } catch (_) {
    return null;
  }
}

/// 选择 login shell。
String _pickShellForLaunch() {
  final preferred = Platform.environment['SHELL']?.trim();
  if (preferred != null && preferred.isNotEmpty && File(preferred).existsSync()) {
    return preferred;
  }
  if (File('/bin/zsh').existsSync()) return '/bin/zsh';
  return '/bin/bash';
}
