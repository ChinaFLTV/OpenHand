import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/hex_encoding.dart';
import 'ai_jungler_client.dart';

const Duration _kAiJunglerLaunchTimeout = Duration(seconds: 10);
const Duration _kAiJunglerReadyTimeout = Duration(seconds: 12);
const Duration _kAiJunglerStopTimeout = Duration(seconds: 2);
const Duration _kAiJunglerCleanupTimeout = Duration(seconds: 5);
const Duration _kAiJunglerStdinTimeout = Duration(seconds: 2);
const Duration _kAiJunglerFileIoTimeout = Duration(seconds: 3);
const Duration _kAiJunglerFileReadTimeout = Duration(seconds: 15);
const int _kAiJunglerMaxLogLineCharacters = 16 * kBytesPerKiB;
const String _kAiJunglerExecutableName = 'ai_jungler';

class AiJunglerRuntime {
  final StreamController<String> _logs = StreamController<String>.broadcast();
  final StreamController<int> _exits = StreamController<int>.broadcast();
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  AiJunglerClient? _client;
  Future<AiJunglerClient>? _bundledStart;
  final OpenHandAsyncOnce _disposeOnce = OpenHandAsyncOnce();
  int _generation = 0;
  bool _disposed = false;

  Stream<String> get logs => _logs.stream;
  Stream<int> get exits => _exits.stream;
  AiJunglerClient? get client => _client;
  bool get ownsProcess => _process != null;

  Future<AiJunglerClient> startBundled() async {
    if (_disposed) throw StateError('扫描运行时已释放。');
    final active = _client;
    if (active != null) return active;
    final pending = _bundledStart;
    if (pending != null) return pending;
    final generation = ++_generation;
    final operation = _startBundled(generation);
    _bundledStart = operation;
    try {
      return await operation;
    } finally {
      if (identical(_bundledStart, operation)) _bundledStart = null;
    }
  }

  Future<AiJunglerClient> _startBundled(int generation) async {
    final executable = await _resolveExecutable();
    final dataDirectory = Directory(
      OpenHandPaths.defaultAiExposureServiceDirectoryPath(),
    );
    await dataDirectory
        .create(recursive: true)
        .timeout(_kAiJunglerFileIoTimeout);
    final token = _newSessionToken();
    final ready = Completer<({Uri address, String version})>();
    final stdoutDone = Completer<void>();
    Process? startedProcess;
    try {
      final process = await startTrackedProcessBounded(
        executable,
        <String>[
          'serve',
          '--data-dir',
          dataDirectory.path,
          '--listen',
          '127.0.0.1:0',
        ],
        timeout: _kAiJunglerLaunchTimeout,
        tag: 'ai_jungler_runtime',
        startInNewProcessGroup: true,
      );
      startedProcess = process;
      if (_disposed || generation != _generation) {
        throw StateError('扫描引擎启动已取消。');
      }
      _process = process;
      final stdoutDecoder = BoundedProcessLineDecoder(
        maxCharacters: _kAiJunglerMaxLogLineCharacters,
        onLine: (line) {
          if (_disposed || generation != _generation) return;
          if (!ready.isCompleted) {
            final parsed = _parseReadyLine(line);
            if (parsed != null) {
              ready.complete(parsed);
              return;
            }
          }
          if (line.trim().isNotEmpty) _logs.add(line);
        },
      );
      _stdoutSubscription = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            stdoutDecoder.add,
            onError: (Object error, StackTrace stack) {
              if (!stdoutDone.isCompleted) stdoutDone.complete();
              if (_disposed || generation != _generation) return;
              silentLog('ai_jungler_runtime', '读取扫描引擎标准输出', error, stack);
            },
            onDone: () {
              stdoutDecoder.close();
              if (!stdoutDone.isCompleted) stdoutDone.complete();
            },
            cancelOnError: true,
          );
      final stderrDecoder = BoundedProcessLineDecoder(
        maxCharacters: _kAiJunglerMaxLogLineCharacters,
        onLine: (line) {
          if (_disposed || generation != _generation) return;
          if (line.trim().isNotEmpty) _logs.add(line);
        },
      );
      _stderrSubscription = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            stderrDecoder.add,
            onError: (Object error, StackTrace stack) {
              if (_disposed || generation != _generation) return;
              silentLog('ai_jungler_runtime', '读取扫描引擎错误输出', error, stack);
            },
            onDone: stderrDecoder.close,
            cancelOnError: true,
          );
      await _sendSessionToken(process, token);
      unawaited(
        _watchExit(process).then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) =>
              silentLog('ai_jungler_runtime', '监听扫描引擎退出', error, stack),
        ),
      );
      final bootstrap = await Future.any<({Uri address, String version})>(
        <Future<({Uri address, String version})>>[
          ready.future,
          stdoutDone.future.then((_) {
            if (ready.isCompleted) return ready.future;
            throw StateError('扫描引擎未返回启动信息。');
          }),
        ],
      ).timeout(_kAiJunglerReadyTimeout);
      if (_disposed ||
          generation != _generation ||
          !identical(_process, process)) {
        throw StateError('扫描引擎在启动期间退出。');
      }
      final client = AiJunglerClient(
        baseUri: bootstrap.address,
        accessToken: token,
        httpClient: SystemProxyResolver.instance.createRawHttpClient(),
      );
      try {
        await client.health();
        if (_disposed ||
            generation != _generation ||
            !identical(_process, process)) {
          throw StateError('扫描引擎启动已取消。');
        }
        _client = client;
        return client;
      } catch (_) {
        client.close();
        rethrow;
      }
    } catch (_) {
      final process = startedProcess;
      if (process != null) {
        await runAsyncCleanupBounded(
          () => terminateTrackedProcessTree(
            process,
            gracefulTimeout: _kAiJunglerStopTimeout,
          ),
          timeout: _kAiJunglerCleanupTimeout,
          onError: (error, stack) =>
              silentLog('ai_jungler_runtime', '清理启动失败的扫描引擎', error, stack),
        );
      }
      if (process != null && identical(_process, process)) {
        await _clearProcessState();
      }
      rethrow;
    }
  }

  Future<AiJunglerClient> connectExternal({
    required Uri address,
    required String accessToken,
  }) async {
    if (_disposed) throw StateError('扫描运行时已释放。');
    final normalizedAddress = _normalizeExternalAddress(address);
    final normalizedToken = accessToken.trim();
    if (normalizedToken.isEmpty) {
      throw const FormatException('访问令牌不能为空。');
    }
    final generation = ++_generation;
    final client = AiJunglerClient(
      baseUri: normalizedAddress,
      accessToken: normalizedToken,
      httpClient: SystemProxyResolver.instance.createRawHttpClient(),
    );
    try {
      await client.health();
      if (_disposed || generation != _generation) {
        throw StateError('外部扫描服务连接已取消。');
      }
      await _stopCurrent();
      if (_disposed || generation != _generation) {
        throw StateError('外部扫描服务连接已取消。');
      }
      _client = client;
      return client;
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  bool isConnectedToExternalAddress(String value) {
    final address = Uri.tryParse(value.trim());
    if (address == null || _process != null) return false;
    try {
      return _client?.baseUri == _normalizeExternalAddress(address);
    } on FormatException {
      return false;
    }
  }

  Future<void> stop() async {
    _generation++;
    await _stopCurrent();
  }

  Future<void> _stopCurrent() async {
    _client?.close();
    _client = null;
    final process = _process;
    _process = null;
    try {
      if (process != null) {
        await runAsyncCleanupBounded(
          () => terminateTrackedProcessTree(
            process,
            gracefulTimeout: _kAiJunglerStopTimeout,
          ),
          timeout: _kAiJunglerCleanupTimeout,
          onError: (error, stack) =>
              silentLog('ai_jungler_runtime', '终止扫描引擎进程', error, stack),
        );
      }
    } finally {
      await _cancelSubscriptions();
    }
  }

  Future<void> dispose() => _disposeOnce.run(_dispose);

  Future<void> _dispose() async {
    _disposed = true;
    _generation++;
    final pendingStart = _bundledStart;
    await runAsyncCleanupBounded(
      _stopCurrent,
      timeout: _kAiJunglerCleanupTimeout,
      onError: (error, stack) =>
          silentLog('ai_jungler_runtime', '停止扫描引擎', error, stack),
    );
    if (pendingStart != null) {
      await runAsyncCleanupBounded(
        () => pendingStart,
        timeout: _kAiJunglerCleanupTimeout,
      );
      await runAsyncCleanupBounded(
        _stopCurrent,
        timeout: _kAiJunglerCleanupTimeout,
        onError: (error, stack) =>
            silentLog('ai_jungler_runtime', '清理迟到的扫描引擎', error, stack),
      );
    }
    await Future.wait<bool>(<Future<bool>>[
      runAsyncCleanupBounded(
        _logs.close,
        timeout: _kAiJunglerCleanupTimeout,
        onError: (error, stack) =>
            silentLog('ai_jungler_runtime', '关闭扫描引擎日志流', error, stack),
      ),
      runAsyncCleanupBounded(
        _exits.close,
        timeout: _kAiJunglerCleanupTimeout,
        onError: (error, stack) =>
            silentLog('ai_jungler_runtime', '关闭扫描引擎退出流', error, stack),
      ),
    ]);
  }

  Future<void> _watchExit(Process process) async {
    final exitCode = await process.exitCode;
    if (!identical(_process, process)) return;
    _process = null;
    _client?.close();
    _client = null;
    await _cancelSubscriptions();
    if (!_exits.isClosed) _exits.add(exitCode);
  }

  Future<void> _clearProcessState() async {
    _process = null;
    _client?.close();
    _client = null;
    await _cancelSubscriptions();
  }

  Future<void> _cancelSubscriptions() async {
    final stdoutSubscription = _stdoutSubscription;
    final stderrSubscription = _stderrSubscription;
    _stdoutSubscription = null;
    _stderrSubscription = null;
    await Future.wait<bool>(<Future<bool>>[
      cancelStreamSubscriptionBounded<String>(
        stdoutSubscription,
        onError: (error, stack) =>
            silentLog('ai_jungler_runtime', '取消扫描引擎标准输出订阅', error, stack),
      ),
      cancelStreamSubscriptionBounded<String>(
        stderrSubscription,
        onError: (error, stack) =>
            silentLog('ai_jungler_runtime', '取消扫描引擎错误输出订阅', error, stack),
      ),
    ]);
  }

  Future<void> _sendSessionToken(Process process, String token) async {
    try {
      process.stdin.writeln(token);
      await process.stdin.flush().timeout(_kAiJunglerStdinTimeout);
    } finally {
      await process.stdin.close().timeout(_kAiJunglerStdinTimeout);
    }
  }

  Future<String> _resolveExecutable() async {
    final override = Platform.environment['OPENHAND_AI_JUNGLER_BINARY']?.trim();
    if (override != null && override.isNotEmpty) {
      final file = File(override);
      if (await file.exists().timeout(_kAiJunglerFileIoTimeout)) {
        return file.path;
      }
      throw FileSystemException('指定的扫描引擎不存在。', override);
    }
    return _extractBundledExecutable(Platform.isWindows ? '.exe' : '');
  }

  Future<String> _extractBundledExecutable(String suffix) async {
    final platformId = _platformAssetId();
    final executable = '$_kAiJunglerExecutableName$suffix';
    final assetRoot = 'assets/ai_jungler/$platformId';
    final assetPath = '$assetRoot/$executable';
    final manifestPath = '$assetRoot/manifest.json';
    Map<String, Object?> manifest;
    ByteData bytes;
    try {
      final decoded = jsonDecode(await rootBundle.loadString(manifestPath));
      if (decoded is! Map) throw const FormatException('扫描引擎清单格式无效。');
      manifest = decoded.map((key, value) => MapEntry('$key', value));
      bytes = await rootBundle.load(assetPath);
    } on FlutterError {
      throw UnsupportedError('当前平台未内置 AI 基础设施扫描引擎：$platformId。');
    }
    final expectedHash = '${manifest['sha256'] ?? ''}'.trim().toLowerCase();
    if (manifest['engine'] != _kAiJunglerExecutableName ||
        manifest['platform'] != platformId ||
        manifest['executable'] != executable ||
        !isLowercaseSha256Hex(expectedHash)) {
      throw StateError('内嵌扫描引擎清单无效：$platformId。');
    }
    final binaryBytes = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    if (sha256.convert(binaryBytes).toString() != expectedHash) {
      throw StateError('内嵌扫描引擎完整性校验失败：$platformId。');
    }
    final binaryDirectory = Directory(
      p.join(
        OpenHandPaths.defaultAiExposureServiceDirectoryPath(),
        'bin',
        platformId,
      ),
    );
    await binaryDirectory
        .create(recursive: true)
        .timeout(_kAiJunglerFileIoTimeout);
    final file = File(p.join(binaryDirectory.path, executable));
    var currentHash = '';
    if (await file.exists().timeout(_kAiJunglerFileIoTimeout)) {
      try {
        final currentBytes = await readBoundedFileBytes(
          file,
          maxBytes: binaryBytes.length,
          idleTimeout: _kAiJunglerFileIoTimeout,
          totalTimeout: _kAiJunglerFileReadTimeout,
        );
        currentHash = sha256.convert(currentBytes).toString();
      } on BoundedFileReadException {
        // 文件过大或校验期间变化时，重新发布内置二进制。
      }
    }
    if (currentHash != expectedHash) {
      await writeBytesFileAtomically(file, binaryBytes);
    }
    if (!Platform.isWindows) {
      final result = await runProcessWithTimeout('chmod', <String>[
        '700',
        file.path,
      ], timeout: const Duration(seconds: 3));
      if (result?.exitCode != 0) {
        throw FileSystemException('设置扫描引擎执行权限失败。', file.path);
      }
    }
    return file.path;
  }

  ({Uri address, String version})? _parseReadyLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map || decoded['event'] != 'ready') return null;
      final address = Uri.tryParse(
        decoded['address'] is String ? decoded['address'] as String : '',
      );
      if (address == null ||
          !address.isScheme('http') ||
          !isLoopbackHost(address.host) ||
          address.userInfo.isNotEmpty ||
          address.query.isNotEmpty ||
          address.fragment.isNotEmpty ||
          (address.path.isNotEmpty && address.path != '/')) {
        return null;
      }
      return (
        address: address,
        version: decoded['version'] is String
            ? decoded['version'] as String
            : '',
      );
    } on FormatException {
      return null;
    }
  }

  String _platformAssetId() => switch (Abi.current()) {
    Abi.macosArm64 => 'darwin-arm64',
    Abi.macosX64 => 'darwin-x64',
    Abi.windowsArm64 => 'windows-arm64',
    Abi.windowsX64 => 'windows-x64',
    Abi.linuxArm64 => 'linux-arm64',
    Abi.linuxX64 => 'linux-x64',
    _ => throw UnsupportedError('当前处理器架构不受支持：${Abi.current()}。'),
  };

  String _newSessionToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

Uri _normalizeExternalAddress(Uri address) {
  final scheme = address.scheme.toLowerCase();
  final host = address.host.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') ||
      host.isEmpty ||
      address.userInfo.isNotEmpty ||
      address.query.isNotEmpty ||
      address.fragment.isNotEmpty ||
      (address.path.isNotEmpty && address.path != '/')) {
    throw const FormatException('服务地址必须是有效的 HTTP/HTTPS 根地址。');
  }
  if (scheme == 'http' && !isLoopbackHost(host)) {
    throw const FormatException('非本机扫描服务必须使用 HTTPS。');
  }
  return address.replace(scheme: scheme, host: host, path: '/');
}
