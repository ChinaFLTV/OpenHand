// 通过 stdio 启动 LSP 服务端并实现 initialize、文档同步、hover、
// definition 与 rename。单个客户端最多维护一个子进程；启动失败、协议错误
// 和请求超时均优雅降级，不影响 Sources 面板的基础功能。

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/bounded_json_conversion.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/message_frame_scan.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/timer_safety.dart';
import '../../../shared/util/user_failure_message.dart';
import '../../../shared/util/version_compare.dart';

/// 当前 LSP 子进程状态。
enum WebReverseLspStatus { idle, starting, ready, notInstalled, failed }

const int _kMaxLspFrameBytes = 8 * kBytesPerMiB;
const int _kMaxLspHeaderBytes = 64 * kBytesPerKiB;
const int _kMaxLspBufferedBytes = _kMaxLspFrameBytes + _kMaxLspHeaderBytes;
const BoundedJsonConversionConfig _kLspJsonConversionConfig =
    kOpenHandProtocolJsonConversionConfig;
const int _kMaxLspStderrCharacters = 256;
const Duration _kDefaultLspRequestTimeout = Duration(seconds: 8);
const Duration _kDefaultLspStartupTimeout = Duration(seconds: 8);
const Duration _kLspTerminationTimeout = Duration(seconds: 4);
const Duration _kLspStreamCancellationTimeout = Duration(seconds: 1);
const int _kMaxPendingLspRequests = 256;
const int _kMaxOpenLspDocuments = 256;
const int _kMaxLspMessagesPerDrain = 64;
final int _maxLspContentLengthDigits = _kMaxLspFrameBytes.toString().length;

class WebReverseLspClient {
  Process? _proc;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  Future<void>? _cleanupFuture;
  final List<int> _buf = <int>[];
  int _nextId = 1;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  bool _bufferDrainScheduled = false;

  WebReverseLspStatus status = WebReverseLspStatus.idle;
  String? lastError;
  // 每个服务端会话独立维护文档版本；新会话必须重新发送 didOpen。
  final LinkedHashMap<String, int> _documentVersions =
      LinkedHashMap<String, int>();
  // initialize 完成信号，避免在服务端握手前发送请求。
  Completer<bool>? _initDone;
  int _lifecycleGeneration = 0;

  /// 启动子进程并完成 LSP initialize 握手。
  Future<bool> start({String? cmd, List<String>? cmdArgs}) async {
    if (status == WebReverseLspStatus.ready) return true;
    if (status == WebReverseLspStatus.starting && _initDone != null) {
      return _initDone!.future;
    }
    final generation = ++_lifecycleGeneration;
    final initDone = Completer<bool>();
    status = WebReverseLspStatus.starting;
    lastError = null;
    _initDone = initDone;
    _buf.clear();
    _bufferDrainScheduled = false;
    _documentVersions.clear();
    _failPendingRequests('进程已重启');
    await _cleanupCurrentProcess();
    if (generation != _lifecycleGeneration) {
      _completeInitialization(initDone, false);
      return false;
    }
    final c = cmd ?? 'typescript-language-server';
    final a = cmdArgs ?? const ['--stdio'];
    late final Process process;
    try {
      final environment = await _augmentedEnvironment();
      if (generation != _lifecycleGeneration) {
        _completeInitialization(initDone, false);
        return false;
      }
      process = await startTrackedProcessBounded(
        c,
        a,
        timeout: _kDefaultLspStartupTimeout,
        tag: 'web_reverse_lsp_client',
        runInShell: true,
        startInNewProcessGroup: true,
        // macOS GUI 启动的 Flutter 进程 PATH 默认是
        // /usr/bin:/bin:/usr/sbin:/sbin，找不到 npm 全局 bin（Apple
        // Silicon 在 /opt/homebrew/bin、Intel 在 /usr/local/bin、nvm 在
        // ~/.nvm/versions/node/.../bin）。这里按常见路径拼一份扩展 PATH，
        // 让 typescript-language-server / pyright 等命令能直接跑起来。
        environment: environment,
      );
    } on TimeoutException {
      if (generation == _lifecycleGeneration) {
        status = WebReverseLspStatus.failed;
        lastError = '进程启动超时';
      }
      _completeInitialization(initDone, false);
      return false;
    } catch (error, stack) {
      if (generation == _lifecycleGeneration) {
        silentLog('web_reverse_lsp_client', '启动进程', error, stack);
        status = WebReverseLspStatus.notInstalled;
        lastError = userFailureMessage(
          error,
          fallback: '无法启动 LSP 进程，请检查命令与安装状态。',
        );
      }
      _completeInitialization(initDone, false);
      return false;
    }
    if (generation != _lifecycleGeneration) {
      await _terminateDetachedProcess(process);
      _completeInitialization(initDone, false);
      return false;
    }
    _proc = process;
    unawaited(
      process.exitCode.then<void>(
        (code) => _handleProcessExit(process, generation, code),
        onError: (Object error, StackTrace stack) {
          if (!identical(_proc, process) ||
              generation != _lifecycleGeneration) {
            return;
          }
          silentLog('web_reverse_lsp_client', '监听进程退出', error, stack);
          _handleProcessExit(process, generation, null);
        },
      ),
    );
    unawaited(
      process.stdin.done.then<void>(
        (_) {
          if (!identical(_proc, process) ||
              generation != _lifecycleGeneration) {
            return;
          }
          _failProtocol('LSP 标准输入意外关闭');
        },
        onError: (Object error, StackTrace stack) {
          if (!identical(_proc, process) ||
              generation != _lifecycleGeneration) {
            return;
          }
          _failProtocol('LSP 标准输入异常。', cause: error, stack: stack);
        },
      ),
    );
    _stdoutSub = process.stdout.listen(
      (bytes) {
        if (!identical(_proc, process) || generation != _lifecycleGeneration) {
          return;
        }
        _onStdout(bytes);
      },
      onError: (Object error, StackTrace stack) {
        if (!identical(_proc, process) || generation != _lifecycleGeneration) {
          return;
        }
        _failProtocol('LSP 标准输出异常。', cause: error, stack: stack);
      },
      onDone: () {
        if (!identical(_proc, process) || generation != _lifecycleGeneration) {
          return;
        }
        _failProtocol('LSP 标准输出意外关闭');
      },
    );
    _stderrSub = process.stderr.listen(
      (bytes) {
        if (!identical(_proc, process) || generation != _lifecycleGeneration) {
          return;
        }
        lastError = clipText(
          utf8.decode(bytes, allowMalformed: true),
          _kMaxLspStderrCharacters,
          suffix: '',
        );
      },
      onError: (Object error, StackTrace stack) {
        if (!identical(_proc, process) || generation != _lifecycleGeneration) {
          return;
        }
        silentLog('web_reverse_lsp_client', '读取标准错误流', error, stack);
      },
    );
    final initRes = await _request('initialize', {
      'processId': pid,
      'rootUri': null,
      'capabilities': <String, Object?>{
        'textDocument': <String, Object?>{
          'synchronization': <String, Object?>{
            'didSave': true,
            'willSave': false,
            'willSaveWaitUntil': false,
          },
          'hover': <String, Object?>{
            'contentFormat': <String>['plaintext', 'markdown'],
          },
          'definition': <String, Object?>{'linkSupport': false},
          'rename': <String, Object?>{'prepareSupport': false},
        },
      },
      'workspaceFolders': null,
    });
    if (generation != _lifecycleGeneration || !identical(_proc, process)) {
      _completeInitialization(initDone, false);
      return false;
    }
    if (initRes == null) {
      status = WebReverseLspStatus.failed;
      lastError ??= '初始化超时';
      await _cleanupCurrentProcess();
      _completeInitialization(initDone, false);
      return false;
    }
    _notify('initialized', <String, Object?>{});
    if (generation != _lifecycleGeneration || !identical(_proc, process)) {
      _completeInitialization(initDone, false);
      return false;
    }
    status = WebReverseLspStatus.ready;
    lastError = null;
    _completeInitialization(initDone, true);
    return true;
  }

  void _handleProcessExit(Process process, int generation, int? code) {
    if (!identical(_proc, process) || generation != _lifecycleGeneration) {
      return;
    }
    _lifecycleGeneration += 1;
    final stdoutSub = _stdoutSub;
    final stderrSub = _stderrSub;
    _proc = null;
    _stdoutSub = null;
    _stderrSub = null;
    _bufferDrainScheduled = false;
    _buf.clear();
    _documentVersions.clear();
    if (status == WebReverseLspStatus.ready ||
        status == WebReverseLspStatus.starting) {
      status = WebReverseLspStatus.failed;
      lastError = code == null ? '无法获取进程退出状态' : '进程退出码：$code';
    }
    _failPendingRequests('进程已退出');
    final initDone = _initDone;
    if (initDone != null) _completeInitialization(initDone, false);
    _observeCleanup(
      _enqueueCleanup(
        () => _releaseDetachedProcess(process, stdoutSub, stderrSub),
      ),
    );
  }

  void _completeInitialization(Completer<bool> completer, bool value) {
    if (!completer.isCompleted) completer.complete(value);
    if (identical(_initDone, completer)) _initDone = null;
  }

  Future<void> stop() async {
    _lifecycleGeneration += 1;
    final initDone = _initDone;
    _initDone = null;
    if (initDone != null && !initDone.isCompleted) initDone.complete(false);
    status = WebReverseLspStatus.idle;
    lastError = null;
    _bufferDrainScheduled = false;
    _buf.clear();
    _documentVersions.clear();
    _failPendingRequests('进程已停止');
    await _cleanupCurrentProcess();
  }

  Future<void> _cleanupCurrentProcess() {
    final process = _proc;
    final stdoutSub = _stdoutSub;
    final stderrSub = _stderrSub;
    _proc = null;
    _stdoutSub = null;
    _stderrSub = null;
    if (process == null && stdoutSub == null && stderrSub == null) {
      return _cleanupFuture ?? Future<void>.value();
    }
    return _enqueueCleanup(() {
      if (process != null) {
        return _releaseDetachedProcess(process, stdoutSub, stderrSub);
      }
      return _cancelSubscriptions(stdoutSub, stderrSub);
    });
  }

  Future<void> _enqueueCleanup(Future<void> Function() operation) {
    final previous = _cleanupFuture;
    late final Future<void> tracked;
    tracked =
        (() async {
          if (previous != null) {
            try {
              await previous;
            } catch (error, stack) {
              silentLog('web_reverse_lsp_client', '等待上一次资源清理', error, stack);
            }
          }
          await operation();
        })().whenComplete(() {
          if (identical(_cleanupFuture, tracked)) _cleanupFuture = null;
        });
    _cleanupFuture = tracked;
    return tracked;
  }

  Future<void> _releaseDetachedProcess(
    Process process,
    StreamSubscription<List<int>>? stdoutSub,
    StreamSubscription<List<int>>? stderrSub,
  ) async {
    await _terminateDetachedProcess(process);
    await _cancelSubscriptions(stdoutSub, stderrSub);
  }

  Future<void> _cancelSubscriptions(
    StreamSubscription<List<int>>? stdoutSub,
    StreamSubscription<List<int>>? stderrSub,
  ) async {
    await Future.wait<bool>(<Future<bool>>[
      cancelStreamSubscriptionBounded<List<int>>(
        stdoutSub,
        timeout: _kLspStreamCancellationTimeout,
        onError: (error, stack) =>
            silentLog('web_reverse_lsp_client', '取消标准输出订阅', error, stack),
      ),
      cancelStreamSubscriptionBounded<List<int>>(
        stderrSub,
        timeout: _kLspStreamCancellationTimeout,
        onError: (error, stack) =>
            silentLog('web_reverse_lsp_client', '取消标准错误订阅', error, stack),
      ),
    ]);
  }

  Future<void> _terminateDetachedProcess(Process process) async {
    try {
      await terminateTrackedProcessTree(
        process,
      ).timeout(_kLspTerminationTimeout);
    } catch (error, stack) {
      silentLog('web_reverse_lsp_client', '终止进程', error, stack);
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (killError, killStack) {
        silentLog('web_reverse_lsp_client', '强制终止进程', killError, killStack);
      }
    }
  }

  void _failPendingRequests(String error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(<String, Object?>{'error': error});
      }
    }
    _pending.clear();
  }

  /// 把当前进程 PATH 与常见的 LSP 安装目录拼起来，避免 GUI 启动的 Flutter
  /// 子进程因为 PATH 不全导致 npm/brew 全局 bin 命令都找不到。仅在 macOS
  /// 与 Linux 下生效，Windows 直接返回原样让 PowerShell 自己解析。
  Future<Map<String, String>> _augmentedEnvironment() async {
    final base = Map<String, String>.from(Platform.environment);
    if (Platform.isWindows) return base;
    final home = base['HOME'] ?? '';
    final extras = <String>[
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/opt/homebrew/sbin',
      '/usr/local/sbin',
      if (home.isNotEmpty) '$home/.local/bin',
      if (home.isNotEmpty) '$home/bin',
      if (home.isNotEmpty) '$home/.npm-global/bin',
      if (home.isNotEmpty) '$home/.bun/bin',
      if (home.isNotEmpty) '$home/.cargo/bin',
      if (home.isNotEmpty) '$home/go/bin',
    ];
    // nvm 安装路径：~/.nvm/versions/node/<version>/bin。当前活跃 node 一
    // 般已经导出在 PATH 里了；这里只补「最近一个版本」做兜底。
    if (home.isNotEmpty) {
      try {
        final nvmRoot = Directory('$home/.nvm/versions/node');
        if (await isDirectoryPath(nvmRoot.path)) {
          final listing = await listDirectoryBounded(
            nvmRoot,
            maxEntries: 256,
            idleTimeout: const Duration(milliseconds: 500),
            totalTimeout: const Duration(seconds: 1),
          );
          final versions =
              listing.entries
                  .whereType<Directory>()
                  .map((directory) => p.basename(directory.path))
                  .where((version) => version.startsWith('v'))
                  .toList(growable: false)
                ..sort(compareSemanticVersions);
          if (versions.isNotEmpty) {
            extras.add(p.join(nvmRoot.path, versions.last, 'bin'));
          }
        }
      } catch (error, stack) {
        silentLog('web_reverse_lsp_client', '扫描 NVM 路径', error, stack);
      }
    }
    final origin = (base['PATH'] ?? '').split(':');
    final seen = <String>{};
    final merged = <String>[];
    for (final p in [...extras, ...origin]) {
      if (p.isEmpty) continue;
      if (seen.add(p)) merged.add(p);
    }
    base['PATH'] = merged.join(':');
    return base;
  }

  /// 第一次访问某文件发送 didOpen；同一会话内后续访问发送全量 didChange。
  Future<void> openOrChange({
    required String uri,
    required String languageId,
    required String text,
  }) async {
    if (status != WebReverseLspStatus.ready) return;
    final previousVersion = _documentVersions[uri];
    if (previousVersion == null) {
      while (_documentVersions.length >= _kMaxOpenLspDocuments) {
        final oldestUri = _documentVersions.keys.first;
        _documentVersions.remove(oldestUri);
        if (!_notify('textDocument/didClose', <String, Object?>{
          'textDocument': <String, Object?>{'uri': oldestUri},
        })) {
          return;
        }
      }
      if (!_notify('textDocument/didOpen', <String, Object?>{
        'textDocument': <String, Object?>{
          'uri': uri,
          'languageId': languageId,
          'version': 1,
          'text': text,
        },
      })) {
        return;
      }
      _documentVersions[uri] = 1;
    } else {
      final version = previousVersion + 1;
      if (!_notify('textDocument/didChange', <String, Object?>{
        'textDocument': <String, Object?>{'uri': uri, 'version': version},
        'contentChanges': <Object?>[
          <String, Object?>{'text': text},
        ],
      })) {
        return;
      }
      _documentVersions.remove(uri);
      _documentVersions[uri] = version;
    }
  }

  /// hover：返回 markdown 字符串；找不到 / 超时返回 null。
  Future<String?> hover(String uri, int line, int character) async {
    if (status != WebReverseLspStatus.ready) return null;
    final r = await _request('textDocument/hover', <String, Object?>{
      'textDocument': <String, Object?>{'uri': uri},
      'position': <String, Object?>{'line': line, 'character': character},
    });
    if (r == null) return null;
    final result = r['result'];
    if (result is! Map) return null;
    final contents = result['contents'];
    if (contents is String) return contents;
    if (contents is Map) {
      return optionalStringFromValue(contents['value']);
    }
    if (contents is List) {
      final parts = <String>[];
      for (final content in contents) {
        final text = content is String
            ? content
            : content is Map
            ? optionalStringFromValue(content['value'])
            : null;
        if (text != null && text.isNotEmpty) parts.add(text);
      }
      return parts.isEmpty ? null : parts.join('\n\n');
    }
    return null;
  }

  /// definition：返回首个目标位置 (uri, line, character)；找不到返回 null。
  Future<({String uri, int line, int character})?> definition(
    String uri,
    int line,
    int character,
  ) async {
    if (status != WebReverseLspStatus.ready) return null;
    final r = await _request('textDocument/definition', <String, Object?>{
      'textDocument': <String, Object?>{'uri': uri},
      'position': <String, Object?>{'line': line, 'character': character},
    });
    if (r == null) return null;
    final result = r['result'];
    if (result == null) return null;
    Map<String, Object?>? loc;
    if (result is List && result.isNotEmpty && result.first is Map) {
      loc = stringKeyedMapFromValue(result.first);
    } else if (result is Map) {
      loc = stringKeyedMapFromValue(result);
    }
    if (loc == null) return null;
    final tgtUri = '${loc['uri'] ?? loc['targetUri'] ?? ''}'.trim();
    if (tgtUri.isEmpty) return null;
    final range = stringKeyedMapFromValue(
      loc['range'] ?? loc['targetSelectionRange'] ?? loc['targetRange'],
    );
    final start = stringKeyedMapFromValue(range['start']);
    final ln = nonNegativeIntFromValue(start['line'], fallback: 0);
    final ch = nonNegativeIntFromValue(start['character'], fallback: 0);
    return (uri: tgtUri, line: ln, character: ch);
  }

  /// rename：返回 LSP WorkspaceEdit 原始 JSON；上层负责解析后落盘。
  /// 这里返回 null 表示不支持或超时。
  Future<Map<String, Object?>?> rename(
    String uri,
    int line,
    int character,
    String newName,
  ) async {
    if (status != WebReverseLspStatus.ready) return null;
    final r = await _request('textDocument/rename', <String, Object?>{
      'textDocument': <String, Object?>{'uri': uri},
      'position': <String, Object?>{'line': line, 'character': character},
      'newName': newName,
    });
    if (r == null) return null;
    final result = r['result'];
    return result is Map ? stringKeyedMapFromValue(result) : null;
  }

  // 内部：JSON-RPC 收发

  Future<Map<String, Object?>?> _request(
    String method,
    Map<String, Object?> params, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _kDefaultLspRequestTimeout;
    if (_pending.length >= _kMaxPendingLspRequests) {
      lastError =
          'LSP 待处理请求过多'
          '（${_pending.length}/$_kMaxPendingLspRequests）。';
      return null;
    }
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    final sent = _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    if (!sent) {
      _pending.remove(id);
      return null;
    }
    try {
      final res = await completer.future.timeout(effectiveTimeout);
      if (res['error'] != null) return null;
      return res;
    } on TimeoutException {
      _pending.remove(id);
      return null;
    }
  }

  bool _notify(String method, Map<String, Object?> params) {
    return _send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  bool _send(Map<String, Object?> msg) {
    final p = _proc;
    if (p == null) return false;
    try {
      final body = utf8.encode(jsonEncode(msg));
      if (body.length > _kMaxLspFrameBytes) {
        lastError = 'LSP 出站消息超过 $_kMaxLspFrameBytes 字节上限';
        return false;
      }
      final header = 'Content-Length: ${body.length}\r\n\r\n';
      p.stdin.add(utf8.encode(header));
      p.stdin.add(body);
      return true;
    } catch (error, stack) {
      _failProtocol('LSP 标准输入写入失败。', cause: error, stack: stack);
      return false;
    }
  }

  void _onStdout(List<int> bytes) {
    if (bytes.length > _kMaxLspBufferedBytes - _buf.length) {
      _failProtocol('LSP 输出缓冲超过 $_kMaxLspBufferedBytes 字节上限');
      return;
    }
    _buf.addAll(bytes);
    if (_bufferDrainScheduled) return;
    _drainStdoutBuffer();
  }

  void _drainStdoutBuffer() {
    var processedMessages = 0;
    while (_proc != null) {
      final frame = findMessageFrameHeaderEnd(_buf, acceptBareLf: false);
      if (frame == null) {
        if (_buf.length > _kMaxLspHeaderBytes) {
          _failProtocol('LSP 消息头超过 $_kMaxLspHeaderBytes 字节上限');
        }
        return;
      }
      final header = utf8.decode(
        _buf.sublist(0, frame.headerEnd),
        allowMalformed: true,
      );
      final parsedContentLength = parseHttpContentLengthHeader(
        header,
        maxDigits: _maxLspContentLengthDigits,
      );
      if (!parsedContentLength.found) {
        _failProtocol('LSP 消息缺少 Content-Length 头');
        return;
      }
      final clen = parsedContentLength.value;
      if (clen == null || clen <= 0 || clen > _kMaxLspFrameBytes) {
        _failProtocol('无效的 Content-Length');
        return;
      }
      final bodyStart = frame.bodyStart;
      final bodyEnd = bodyStart + clen;
      if (_buf.length < bodyEnd) return;
      final body = _buf.sublist(bodyStart, bodyEnd);
      _buf.removeRange(0, bodyEnd);
      try {
        final decoded = decodeJsonTextUsingConfig(
          utf8.decode(body),
          maxTextCodeUnits: _kMaxLspFrameBytes,
          config: _kLspJsonConversionConfig,
        );
        if (decoded is Map && decoded['id'] is num) {
          final id = (decoded['id'] as num).toInt();
          final c = _pending.remove(id);
          if (c != null && !c.isCompleted) {
            c.complete(stringKeyedMapFromValue(decoded));
          }
        }
        // notification（无 id）暂不处理。
      } catch (error, stack) {
        _failProtocol('收到无效的 JSON-RPC 载荷。', cause: error, stack: stack);
        return;
      }
      processedMessages += 1;
      if (processedMessages >= _kMaxLspMessagesPerDrain) {
        _scheduleBufferDrain();
        return;
      }
    }
  }

  void _scheduleBufferDrain() {
    if (_bufferDrainScheduled || _buf.isEmpty) return;
    final generation = _lifecycleGeneration;
    _bufferDrainScheduled = true;
    startSafeTimer(
      Duration.zero,
      () {
        if (generation != _lifecycleGeneration) return;
        _bufferDrainScheduled = false;
        _drainStdoutBuffer();
      },
      onError: (error, stack) {
        if (generation != _lifecycleGeneration) return;
        _bufferDrainScheduled = false;
        _failProtocol('处理 LSP 输出失败。', cause: error, stack: stack);
      },
    );
  }

  void _failProtocol(String message, {Object? cause, StackTrace? stack}) {
    final process = _proc;
    final stdoutSub = _stdoutSub;
    final stderrSub = _stderrSub;
    _lifecycleGeneration += 1;
    _proc = null;
    _stdoutSub = null;
    _stderrSub = null;
    _bufferDrainScheduled = false;
    _buf.clear();
    _documentVersions.clear();
    status = WebReverseLspStatus.failed;
    lastError = message;
    _failPendingRequests(message);
    final initDone = _initDone;
    if (initDone != null) _completeInitialization(initDone, false);
    if (process != null) {
      _observeCleanup(
        _enqueueCleanup(
          () => _releaseDetachedProcess(process, stdoutSub, stderrSub),
        ),
      );
    } else {
      _observeCleanup(
        _enqueueCleanup(() => _cancelSubscriptions(stdoutSub, stderrSub)),
      );
    }
    silentLog(
      'web_reverse_lsp_client',
      '处理协议消息',
      cause ?? message,
      stack ?? StackTrace.current,
    );
  }

  void _observeCleanup(Future<void> cleanup) {
    unawaited(
      cleanup.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) =>
            silentLog('web_reverse_lsp_client', '后台清理进程资源', error, stack),
      ),
    );
  }
}
