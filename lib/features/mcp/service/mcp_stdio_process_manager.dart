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

    _processes[name] = const _ManagedProcess(
      info: StdioProcessInfo(state: StdioProcessState.starting),
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

      final responseRouter = _ManagedResponseRouter();
      final managed = _ManagedProcess(
        info: StdioProcessInfo(
          state: StdioProcessState.running,
          pid: process.pid,
          startedAt: DateTime.now().toUtc(),
          logs: List.unmodifiable(logs),
        ),
        process: process,
        responseRouter: responseRouter,
      );
      _processes[name] = managed;
      notifyListeners();

      // 监听 stdout - 同时用于日志、握手响应检测和 discovery 响应路由
      final handshakeCompleter = Completer<bool>();
      process.stdout.transform(utf8.decoder).listen(
        (data) {
          // 优先尝试路由到 discovery session 的 pending requests
          final routed = responseRouter.tryRoute(data);
          _appendLog(name, data, isStderr: false);
          // 检测 MCP initialize 响应
          if (!handshakeCompleter.isCompleted &&
              (data.contains('"result"') || data.contains('"protocolVersion"'))) {
            handshakeCompleter.complete(true);
          }
          // 如果路由成功但日志已记录，不影响功能
          if (routed) return;
        },
        onError: (e) {
          responseRouter.failAll(e is Object ? e : StateError('$e'));
          _appendLog(name, '[stdout error] $e', isStderr: true);
        },
        onDone: () {
          responseRouter.failAll(StateError('stdout closed'));
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
        responseRouter.failAll(StateError('process exited with code $code'));
        final current = _processes[name];
        if (current != null) {
          _processes[name] = _ManagedProcess(
            info: current.info.copyWith(
              state: StdioProcessState.stopped,
              clearPid: true,
            ),
            responseRouter: current.responseRouter,
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
      handshakeCompleted: managed.handshakeCompleted,
    );
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Discovery Service 复用已运行进程的会话借用机制
  // ─────────────────────────────────────────────────────────────────────────

  final Map<String, int> _sessionBorrowCount = {};

  /// 尝试借用已运行且握手完成的进程供 discovery service 发送 tools/list。
  /// 如果进程正在运行但握手尚未完成，最多等待 [_handshakeWaitTimeout] 秒。
  /// 返回 null 表示无可用进程（未启动/已停止/等待超时），调用方应回退到启动新进程。
  /// 借用期间进程不会被 stopServer 关闭（通过引用计数保护）。
  static const Duration _handshakeWaitTimeout = Duration(seconds: 30);

  Future<ManagedStdioSession?> borrowSessionForDiscovery(
    String serverName,
  ) async {
    _ManagedProcess? managed = _processes[serverName];
    if (managed == null || managed.info.isStopped || managed.process == null) {
      return null;
    }

    // 如果进程正在运行但握手尚未完成，轮询等待
    if (!managed.handshakeCompleted) {
      final deadline = DateTime.now().add(_handshakeWaitTimeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        managed = _processes[serverName];
        if (managed == null || managed.info.isStopped || managed.process == null) {
          return null;
        }
        if (managed.handshakeCompleted) break;
      }
    }

    // 最终检查
    if (managed == null ||
        !managed.handshakeCompleted ||
        managed.process == null ||
        managed.responseRouter == null) {
      return null;
    }
    _sessionBorrowCount[serverName] =
        (_sessionBorrowCount[serverName] ?? 0) + 1;
    return ManagedStdioSession._(managed.process!, managed.responseRouter!);
  }

  /// 归还借用的会话，释放引用计数。
  void returnSession(String serverName) {
    final count = _sessionBorrowCount[serverName] ?? 0;
    if (count <= 1) {
      _sessionBorrowCount.remove(serverName);
    } else {
      _sessionBorrowCount[serverName] = count - 1;
    }
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

      // 使用 JSON-line 模式发送（与 discovery service 保持一致）。
      // Playwright 等主流 MCP 服务使用 JSON-line 解析，
      // Content-Length header 会干扰其消息边界检测。
      process.stdin.add(utf8.encode(initRequest));
      process.stdin.add(const [0x0A]);
      await process.stdin.flush();

      // 等待 stdout 中出现响应（最多 90 秒，npx 首次运行需要下载包）
      final gotResponse = await responseCompleter.future
          .timeout(const Duration(seconds: 90), onTimeout: () => false);

      if (gotResponse) {
        _appendLog(serverName, '[${_timestamp()}] ✓ MCP 握手成功', isStderr: false);

        // 发送 initialized 通知（JSON-line 模式）
        final notification = jsonEncode({
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        });
        process.stdin.add(utf8.encode(notification));
        process.stdin.add(const [0x0A]);
        await process.stdin.flush();
        _appendLog(serverName, '[${_timestamp()}] ✓ 服务已就绪，可正常使用', isStderr: false);

        // 标记握手完成，允许 discovery service 复用此进程
        final current = _processes[serverName];
        if (current != null) {
          _processes[serverName] = _ManagedProcess(
            info: current.info,
            process: current.process,
            handshakeCompleted: true,
            responseRouter: current.responseRouter,
          );
        }
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

/// 轻量级会话包装器，供 discovery service 通过已运行的进程发送 JSON-RPC 请求。
/// 不拥有进程生命周期——进程由 McpStdioProcessManager 管理。
/// 响应路由通过 McpStdioProcessManager 的 stdout 监听器完成。
class ManagedStdioSession {
  ManagedStdioSession._(this._process, this._responseRouter);

  final Process _process;
  final _ManagedResponseRouter _responseRouter;
  String instructions = '';

  static const Duration _requestTimeout = Duration(seconds: 8);

  Future<Map<String, Object?>?> sendRequest(
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    final requestIdText = '${payload['id']}';
    final completer = Completer<Map<String, Object?>?>();
    _responseRouter.register(requestIdText, completer);
    try {
      final body = utf8.encode(jsonEncode(payload));
      _process.stdin.add(body);
      _process.stdin.add(const [0x0A]);
      await _process.stdin.flush();
    } on StateError catch (e) {
      _responseRouter.unregister(requestIdText);
      throw McpToolDiscoveryException(
        'Cannot write to managed stdio process: $e',
      );
    } catch (e) {
      _responseRouter.unregister(requestIdText);
      rethrow;
    }
    try {
      return await completer.future.timeout(timeout ?? _requestTimeout);
    } on TimeoutException {
      _responseRouter.unregister(requestIdText);
      throw const McpToolDiscoveryException(
        'Tool scan timed out waiting for response from managed stdio process.',
      );
    }
  }
}

/// 管理进程 stdout 中 JSON-RPC 响应的路由分发。
/// stdout 数据可能跨多个 chunk 到达（尤其是大的 tools/list 响应），
/// 因此需要内部缓冲并按行边界解析。
class _ManagedResponseRouter {
  final Map<String, Completer<Map<String, Object?>?>> _pending = {};
  final StringBuffer _lineBuffer = StringBuffer();

  void register(String id, Completer<Map<String, Object?>?> completer) {
    _pending[id] = completer;
  }

  void unregister(String id) {
    _pending.remove(id);
  }

  /// 将 stdout 数据喂入路由器。数据可能跨多个 chunk 到达，
  /// 内部按换行符分割并尝试解析完整的 JSON-RPC 响应。
  /// 返回 true 表示成功路由了至少一个响应。
  bool tryRoute(String data) {
    if (_pending.isEmpty) return false;
    _lineBuffer.write(data);
    final buffer = _lineBuffer.toString();
    // 查找最后一个换行符，之前的部分可以尝试解析
    final lastNewline = buffer.lastIndexOf('\n');
    if (lastNewline < 0) return false;
    final complete = buffer.substring(0, lastNewline);
    final remainder = buffer.substring(lastNewline + 1);
    _lineBuffer
      ..clear()
      ..write(remainder);
    bool routed = false;
    for (final line in complete.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('{')) continue;
      try {
        final decoded = jsonDecode(trimmed) as Map<String, Object?>;
        final id = decoded['id'];
        if (id == null) continue;
        final idText = '$id';
        final completer = _pending.remove(idText);
        if (completer != null && !completer.isCompleted) {
          completer.complete(decoded);
          routed = true;
        }
      } catch (_) {
        // JSON 解析失败——可能是非 JSON 输出（如 npm 进度信息），跳过
      }
    }
    return routed;
  }

  void failAll(Object error) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _pending.clear();
    _lineBuffer.clear();
  }

  bool get hasPending => _pending.isNotEmpty;
}

class _ManagedProcess {
  const _ManagedProcess({
    required this.info,
    this.process,
    this.handshakeCompleted = false,
    this.responseRouter,
  });

  final StdioProcessInfo info;
  final Process? process;
  final bool handshakeCompleted;
  final _ManagedResponseRouter? responseRouter;
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

/// 通过多种策略定位 npx 包的实际安装路径和入口脚本。
Future<_ResolvedNpxPackage?> _resolveNpxPackagePath(String packageName) async {
  // 解析包名（处理 @scope/name@version 格式）
  final cleanName = packageName.replaceAll(RegExp(r'@[^/]*$'), '');

  // 策略 1：直接扫描 nvm 目录（最可靠，GUI 应用中 nvm 是最常见的 node 管理器）
  final home = Platform.environment['HOME'] ?? '';
  if (home.isNotEmpty) {
    final nvmDir = Platform.environment['NVM_DIR'] ?? '$home/.nvm';
    final versionsDir = Directory('$nvmDir/versions/node');
    if (versionsDir.existsSync()) {
      // 找到最新版本的 node
      final versions = <String>[];
      try {
        for (final entity in versionsDir.listSync()) {
          if (entity is Directory && entity.path.split('/').last.startsWith('v')) {
            versions.add(entity.path.split('/').last);
          }
        }
      } catch (_) {}
      versions.sort(_compareVersions);
      // 从最新版本开始查找包
      for (final version in versions.reversed) {
        final nodeBin = '$nvmDir/versions/node/$version/bin/node';
        final packageDir = '$nvmDir/versions/node/$version/lib/node_modules/$cleanName';
        if (File(nodeBin).existsSync() && Directory(packageDir).existsSync()) {
          final entry = _findBinEntry(packageDir);
          if (entry != null) {
            return _ResolvedNpxPackage(nodeBin: nodeBin, entryScript: entry);
          }
        }
      }
    }

    // 策略 2：检查 volta
    final voltaDir = '$home/.volta/tools/image/packages';
    if (Directory(voltaDir).existsSync()) {
      // volta 的全局包在 ~/.volta/tools/image/packages/<name>/
      final voltaPkgDir = '$voltaDir/$cleanName';
      if (Directory(voltaPkgDir).existsSync()) {
        final voltaNode = '$home/.volta/bin/node';
        if (File(voltaNode).existsSync()) {
          final entry = _findBinEntry(voltaPkgDir);
          if (entry != null) {
            return _ResolvedNpxPackage(nodeBin: voltaNode, entryScript: entry);
          }
        }
      }
    }
  }

  // 策略 3：通过 login shell 查询（兜底）
  try {
    final shell = _pickShellForLaunch();
    final result = await Process.run(
      shell, ['-l', '-c', 'which node && npm root -g'],
    ).timeout(const Duration(seconds: 8));
    if (result.exitCode == 0) {
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length >= 2) {
        final nodeBin = lines[0].trim();
        final globalRoot = lines[1].trim();
        if (nodeBin.isNotEmpty && globalRoot.isNotEmpty && File(nodeBin).existsSync()) {
          final packageDir = '$globalRoot/$cleanName';
          if (Directory(packageDir).existsSync()) {
            final entry = _findBinEntry(packageDir);
            if (entry != null) {
              return _ResolvedNpxPackage(nodeBin: nodeBin, entryScript: entry);
            }
          }
        }
      }
    }
  } catch (_) {}

  return null;
}

/// 从 package.json 的 bin 字段解析入口脚本路径。
String? _findBinEntry(String packageDir) {
  try {
    final pkgJsonFile = File('$packageDir/package.json');
    if (!pkgJsonFile.existsSync()) return null;
    final pkgJson = jsonDecode(pkgJsonFile.readAsStringSync());
    final bin = pkgJson['bin'];
    String? entryScript;
    if (bin is String) {
      entryScript = '$packageDir/$bin';
    } else if (bin is Map && bin.isNotEmpty) {
      entryScript = '$packageDir/${bin.values.first}';
    }
    if (entryScript != null && File(entryScript).existsSync()) return entryScript;
  } catch (_) {}
  return null;
}

int _compareVersions(String a, String b) {
  final ap = a.substring(1).split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final bp = b.substring(1).split('.').map((s) => int.tryParse(s) ?? 0).toList();
  for (int i = 0; i < 3; i++) {
    final av = i < ap.length ? ap[i] : 0;
    final bv = i < bp.length ? bp[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
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
