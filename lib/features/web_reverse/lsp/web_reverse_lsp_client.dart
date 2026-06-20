// LSP 极简实现：支持把任一 stdio LSP server（默认
// typescript-language-server --stdio）拉起为子进程，按 JSON-RPC 2.0 over
// LSP framing（Content-Length 头）做 initialize / textDocument/didOpen /
// hover / definition / rename 请求。
//
// 设计目标：
// - 默认安装的项目可以零配置直接用；未装 typescript-language-server 时
//   能优雅退化（status='not_installed'），不阻塞 Sources 面板基础功能。
// - 单实例同时只起一份 server 子进程；面板 dispose 时关掉进程。
// - 所有 send 都返回 Future + 唯一 id；超时（默认 8s）resolve null。
//
// 不实现：completion / signature help / 增量同步（didChange 用 full
// content）等高级特性 —— 等用户真有需求再补。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';

/// 当前 LSP 子进程状态。
enum WebReverseLspStatus { idle, starting, ready, notInstalled, failed }

const int _kMaxLspFrameBytes = 8 * 1024 * 1024;

class WebReverseLspClient {
  WebReverseLspClient({this.command, this.args});

  /// LSP server 可执行命令；默认 'typescript-language-server'。用户可在
  /// 「LSP 设置」对话框里改。
  final String? command;
  final List<String>? args;

  Process? _proc;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  final BytesBuilder _buf = BytesBuilder(copy: false);
  int _nextId = 1;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};

  WebReverseLspStatus status = WebReverseLspStatus.idle;
  String? lastError;
  // 已 didOpen 过的 uri；didChange 时若不在则先补 didOpen。
  final Set<String> _opened = <String>{};
  // initialize 完成 future，避免任何请求在 server 还没握手前就发。
  Completer<bool>? _initDone;

  /// 启动子进程并完成 LSP initialize 握手。
  Future<bool> start({String? cmd, List<String>? cmdArgs}) async {
    if (status == WebReverseLspStatus.ready) return true;
    if (status == WebReverseLspStatus.starting && _initDone != null) {
      return _initDone!.future;
    }
    status = WebReverseLspStatus.starting;
    _initDone = Completer<bool>();
    final c = cmd ?? command ?? 'typescript-language-server';
    final a = cmdArgs ?? args ?? const ['--stdio'];
    try {
      _proc = await startTrackedProcess(
        c,
        a,
        runInShell: true,
        // 2026-05-24 — macOS GUI 启动的 Flutter 进程 PATH 默认是
        // /usr/bin:/bin:/usr/sbin:/sbin，找不到 npm 全局 bin（Apple
        // Silicon 在 /opt/homebrew/bin、Intel 在 /usr/local/bin、nvm 在
        // ~/.nvm/versions/node/.../bin）。这里按常见路径拼一份扩展 PATH，
        // 让 typescript-language-server / pyright 等命令能直接跑起来。
        environment: _augmentedEnvironment(),
      );
    } catch (e, st) {
      silentLog('web_reverse_lsp_client', 'spawn', e, st);
      status = WebReverseLspStatus.notInstalled;
      lastError = '$e';
      _initDone!.complete(false);
      return false;
    }
    _proc!.exitCode.then((code) {
      if (status != WebReverseLspStatus.ready &&
          status != WebReverseLspStatus.starting) {
        return;
      }
      status = WebReverseLspStatus.failed;
      lastError = 'exit $code';
      // 把所有挂起请求 resolve 成 error，避免上层 await 永挂。
      for (final c in _pending.values) {
        if (!c.isCompleted) c.complete(<String, Object?>{'error': 'exited'});
      }
      _pending.clear();
    });
    _stdoutSub = _proc!.stdout.listen(_onStdout);
    _stderrSub = _proc!.stderr.listen((bytes) {
      // 限制日志噪音，只记前 256B。
      lastError = utf8.decode(bytes, allowMalformed: true);
    });
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
    if (initRes == null) {
      status = WebReverseLspStatus.failed;
      lastError ??= 'initialize timeout';
      _initDone!.complete(false);
      return false;
    }
    await _notify('initialized', <String, Object?>{});
    status = WebReverseLspStatus.ready;
    _initDone!.complete(true);
    return true;
  }

  Future<void> stop() async {
    try {
      await _stdoutSub?.cancel();
      await _stderrSub?.cancel();
    } catch (error, stack) {
      silentLog('web_reverse_lsp_client', 'cancel streams', error, stack);
    }
    try {
      _proc?.kill();
    } catch (error, stack) {
      silentLog('web_reverse_lsp_client', 'kill process', error, stack);
    }
    _proc = null;
    status = WebReverseLspStatus.idle;
    _buf.clear();
    _initDone = null;
    _opened.clear();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(<String, Object?>{'error': 'stopped'});
    }
    _pending.clear();
  }

  /// 把当前进程 PATH 与常见的 LSP 安装目录拼起来，避免 GUI 启动的 Flutter
  /// 子进程因为 PATH 不全导致 npm/brew 全局 bin 命令都找不到。仅在 macOS
  /// 与 Linux 下生效，Windows 直接返回原样让 PowerShell 自己解析。
  Map<String, String> _augmentedEnvironment() {
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
        if (nvmRoot.existsSync()) {
          final versions =
              nvmRoot
                  .listSync()
                  .whereType<Directory>()
                  .map((d) => d.path)
                  .toList()
                ..sort();
          if (versions.isNotEmpty) extras.add('${versions.last}/bin');
        }
      } catch (error, stack) {
        silentLog('web_reverse_lsp_client', 'scan nvm path', error, stack);
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

  /// 第一次访问某文件 → didOpen；之后再访问同 uri 走 didChange (full)。
  Future<void> openOrChange({
    required String uri,
    required String languageId,
    required String text,
  }) async {
    if (status != WebReverseLspStatus.ready) return;
    if (!_opened.contains(uri)) {
      _opened.add(uri);
      await _notify('textDocument/didOpen', <String, Object?>{
        'textDocument': <String, Object?>{
          'uri': uri,
          'languageId': languageId,
          'version': 1,
          'text': text,
        },
      });
    } else {
      await _notify('textDocument/didChange', <String, Object?>{
        'textDocument': <String, Object?>{
          'uri': uri,
          'version': DateTime.now().millisecondsSinceEpoch,
        },
        'contentChanges': <Object?>[
          <String, Object?>{'text': text},
        ],
      });
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
    if (result == null) return null;
    final contents = (result as Map)['contents'];
    if (contents is String) return contents;
    if (contents is Map) return '${contents['value'] ?? ''}';
    if (contents is List) {
      return contents
          .map((c) => c is String ? c : '${(c as Map)['value'] ?? ''}')
          .where((s) => s.isNotEmpty)
          .join('\n\n');
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
    Map? loc;
    if (result is List && result.isNotEmpty) {
      loc = result.first as Map;
    } else if (result is Map) {
      loc = result;
    }
    if (loc == null) return null;
    final tgtUri = loc['uri'] ?? loc['targetUri'];
    final range =
        (loc['range'] ?? loc['targetSelectionRange'] ?? loc['targetRange'])
            as Map?;
    final start = range?['start'] as Map?;
    final ln = (start?['line'] as num?)?.toInt() ?? 0;
    final ch = (start?['character'] as num?)?.toInt() ?? 0;
    return (uri: '$tgtUri', line: ln, character: ch);
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
    return result is Map ? Map<String, Object?>.from(result) : null;
  }

  // ────────────────────────────────────────────────────────────────────
  // 内部：JSON-RPC 收发
  // ────────────────────────────────────────────────────────────────────

  Future<Map<String, Object?>?> _request(
    String method,
    Map<String, Object?> params, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    try {
      final res = await completer.future.timeout(timeout);
      if (res['error'] != null) return null;
      return res;
    } on TimeoutException {
      _pending.remove(id);
      return null;
    }
  }

  Future<void> _notify(String method, Map<String, Object?> params) async {
    _send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  void _send(Map<String, Object?> msg) {
    final p = _proc;
    if (p == null) return;
    final body = utf8.encode(jsonEncode(msg));
    final header = 'Content-Length: ${body.length}\r\n\r\n';
    try {
      p.stdin.add(utf8.encode(header));
      p.stdin.add(body);
    } catch (error, stack) {
      silentLog('web_reverse_lsp_client', 'send message', error, stack);
    }
  }

  void _onStdout(List<int> bytes) {
    _buf.add(bytes);
    while (true) {
      final all = _buf.toBytes();
      final end = _findHeaderEnd(all);
      if (end < 0) return;
      final header = utf8.decode(all.sublist(0, end));
      final m = RegExp(
        r'Content-Length:\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(header);
      if (m == null) {
        // 不识别头，丢掉之前数据避免死循环。
        _buf.clear();
        return;
      }
      final clen = int.parse(m.group(1)!);
      if (clen <= 0 || clen > _kMaxLspFrameBytes) {
        _buf.clear();
        status = WebReverseLspStatus.failed;
        final errorMessage = 'invalid Content-Length: $clen';
        lastError = errorMessage;
        silentLog(
          'web_reverse_lsp_client',
          'invalid content length',
          errorMessage,
          StackTrace.current,
        );
        return;
      }
      final bodyStart = end + 4;
      if (all.length < bodyStart + clen) return;
      final body = all.sublist(bodyStart, bodyStart + clen);
      _buf.clear();
      _buf.add(all.sublist(bodyStart + clen));
      try {
        final decoded = jsonDecode(utf8.decode(body));
        if (decoded is Map && decoded['id'] is num) {
          final id = (decoded['id'] as num).toInt();
          final c = _pending.remove(id);
          if (c != null && !c.isCompleted) {
            c.complete(Map<String, Object?>.from(decoded));
          }
        }
        // notification（无 id）暂不处理。
      } catch (e, st) {
        silentLog('web_reverse_lsp_client', 'parse', e, st);
      }
    }
  }

  int _findHeaderEnd(List<int> buf) {
    // 找 \r\n\r\n。
    for (var i = 0; i + 3 < buf.length; i++) {
      if (buf[i] == 13 &&
          buf[i + 1] == 10 &&
          buf[i + 2] == 13 &&
          buf[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }
}
