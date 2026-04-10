import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/ai_bash_tool_service.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

/// 2026-04-10 LSP 符号级导航工具 — 通过 Dart Analysis Server 实现真实代码智能。
/// 支持操作：goToDefinition, findReferences, hover, documentSymbol,
///           workspaceSymbol, goToImplementation, prepareCallHierarchy,
///           incomingCalls, outgoingCalls.
///
/// 内部通过 `dart language-server --lsp` 启动独立 LSP 进程，使用 JSON-RPC 2.0 通信。
/// 进程按需启动并缓存复用，30 秒无活动后自动关停以节省资源。
class AiLspTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.lsp;

  @override
  List<String> get aliases => const <String>['Lsp'];

  /// 缓存的 LSP 进程，按 workspace root 索引。
  static final Map<String, _LspSession> _sessions = <String, _LspSession>{};

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();

    final operation = '${args['operation'] ?? ''}'.trim();
    final filePath = '${args['file_path'] ?? ''}'.trim();

    if (operation.isEmpty || filePath.isEmpty) {
      return AiToolUtils.invalidResult(
          'Lsp', 'operation and file_path are required.');
    }

    final resolvedPath = AiToolUtils.resolvePath(filePath);
    final line = AiToolUtils.readInt(args['line']) ?? 1;
    final character = AiToolUtils.readInt(args['character']) ?? 1;

    // 推算 workspace root：向上找 pubspec.yaml / .git
    final rootPath = _inferWorkspaceRoot(resolvedPath);

    try {
      final session = await _getOrCreateSession(rootPath);
      final result = await session.request(
        operation: operation,
        filePath: resolvedPath,
        line: line - 1, // LSP uses 0-based lines
        character: character - 1, // LSP uses 0-based characters
      );

      return AiToolUtils.simpleSuccessResult(
        command: 'Lsp $operation',
        output: result,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(resolvedPath),
      );
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'Lsp $operation',
        workingDirectory: p.dirname(resolvedPath),
        stdout: '',
        stderr: '$error',
        durationMs: startedAt.elapsedMilliseconds,
        resultText:
            'status: failed\nerror: LSP operation "$operation" failed: $error\n'
            'Fallback: use Grep/Glob/Read for code intelligence.',
      );
    }
  }

  static String _inferWorkspaceRoot(String filePath) {
    var dir = Directory(p.dirname(filePath));
    while (true) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() ||
          Directory(p.join(dir.path, '.git')).existsSync() ||
          File(p.join(dir.path, 'package.json')).existsSync() ||
          File(p.join(dir.path, 'go.mod')).existsSync() ||
          File(p.join(dir.path, 'Cargo.toml')).existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return p.dirname(filePath);
  }

  static Future<_LspSession> _getOrCreateSession(String rootPath) async {
    final existing = _sessions[rootPath];
    if (existing != null && existing.isAlive) {
      existing.touch();
      return existing;
    }
    // 清理已死进程
    if (existing != null) {
      _sessions.remove(rootPath);
    }
    final session = _LspSession(rootPath: rootPath);
    await session.initialize();
    _sessions[rootPath] = session;
    return session;
  }

  /// 释放所有 LSP 会话。测试或应用退出时调用。
  static Future<void> disposeAll() async {
    for (final session in _sessions.values) {
      await session.shutdown();
    }
    _sessions.clear();
  }
}

/// 管理一个 `dart language-server --lsp` 进程的生命周期和 JSON-RPC 通信。
class _LspSession {
  _LspSession({required this.rootPath});

  final String rootPath;
  Process? _process;
  int _nextId = 1;
  final Map<int, Completer<Object?>> _pendingRequests = <int, Completer<Object?>>{};
  final StringBuffer _responseBuffer = StringBuffer();
  Timer? _idleTimer;
  static const Duration _idleTimeout = Duration(seconds: 30);
  static const Duration _requestTimeout = Duration(seconds: 15);

  bool get isAlive => _process != null;

  void touch() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () => shutdown());
  }

  Future<void> initialize() async {
    _process = await Process.start('dart', <String>['language-server', '--lsp']);
    _process!.stdout.transform(utf8.decoder).listen(_onData);
    _process!.stderr.drain<void>();

    // Send initialize request
    final initResult = await _sendRequest('initialize', <String, Object?>{
      'processId': pid,
      'rootUri': Uri.file(rootPath).toString(),
      'capabilities': <String, Object?>{
        'textDocument': <String, Object?>{
          'hover': <String, Object?>{'contentFormat': <String>['markdown', 'plaintext']},
          'definition': <String, Object?>{'linkSupport': true},
          'references': <String, Object?>{},
          'documentSymbol': <String, Object?>{
            'hierarchicalDocumentSymbolSupport': true,
          },
          'implementation': <String, Object?>{},
          'callHierarchy': <String, Object?>{},
        },
        'workspace': <String, Object?>{
          'symbol': <String, Object?>{},
        },
      },
    });
    if (initResult == null) {
      throw StateError('LSP initialize returned null');
    }

    // Send initialized notification
    _sendNotification('initialized', <String, Object?>{});
    touch();

    // Wait a moment for the server to index
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  Future<String> request({
    required String operation,
    required String filePath,
    required int line,
    required int character,
  }) async {
    final fileUri = Uri.file(filePath).toString();
    final position = <String, Object?>{
      'line': line,
      'character': character,
    };
    final textDocIdent = <String, Object?>{'uri': fileUri};

    touch();

    switch (operation) {
      case 'goToDefinition':
        final result = await _sendRequest('textDocument/definition', <String, Object?>{
          'textDocument': textDocIdent,
          'position': position,
        });
        return _formatLocationResult(result, 'Definition');

      case 'findReferences':
        final result = await _sendRequest('textDocument/references', <String, Object?>{
          'textDocument': textDocIdent,
          'position': position,
          'context': <String, Object?>{'includeDeclaration': true},
        });
        return _formatLocationResult(result, 'References');

      case 'hover':
        final result = await _sendRequest('textDocument/hover', <String, Object?>{
          'textDocument': textDocIdent,
          'position': position,
        });
        return _formatHoverResult(result);

      case 'documentSymbol':
        final result =
            await _sendRequest('textDocument/documentSymbol', <String, Object?>{
          'textDocument': textDocIdent,
        });
        return _formatSymbolResult(result, 'Document Symbols');

      case 'workspaceSymbol':
        // For workspace symbol, use the file_path as a query string
        final query = filePath.contains('/') ? p.basename(filePath) : filePath;
        final result = await _sendRequest('workspace/symbol', <String, Object?>{
          'query': query,
        });
        return _formatSymbolResult(result, 'Workspace Symbols');

      case 'goToImplementation':
        final result =
            await _sendRequest('textDocument/implementation', <String, Object?>{
          'textDocument': textDocIdent,
          'position': position,
        });
        return _formatLocationResult(result, 'Implementation');

      case 'prepareCallHierarchy':
        final result = await _sendRequest(
            'textDocument/prepareCallHierarchy', <String, Object?>{
          'textDocument': textDocIdent,
          'position': position,
        });
        return _formatCallHierarchyItems(result);

      case 'incomingCalls':
        final prepareResult = await _sendRequest(
            'textDocument/prepareCallHierarchy', <String, Object?>{
          'textDocument': textDocIdent,
          'position': position,
        });
        final items = _parseCallHierarchyItems(prepareResult);
        if (items.isEmpty) return '(no call hierarchy item found at this position)';
        final callsResult = await _sendRequest(
            'callHierarchy/incomingCalls', <String, Object?>{
          'item': items.first,
        });
        return _formatCallResults(callsResult, 'Incoming Calls');

      case 'outgoingCalls':
        final prepareResult = await _sendRequest(
            'textDocument/prepareCallHierarchy', <String, Object?>{
          'textDocument': textDocIdent,
          'position': position,
        });
        final items = _parseCallHierarchyItems(prepareResult);
        if (items.isEmpty) return '(no call hierarchy item found at this position)';
        final callsResult = await _sendRequest(
            'callHierarchy/outgoingCalls', <String, Object?>{
          'item': items.first,
        });
        return _formatCallResults(callsResult, 'Outgoing Calls');

      default:
        return 'Unknown LSP operation: $operation. Supported: goToDefinition, '
            'findReferences, hover, documentSymbol, workspaceSymbol, '
            'goToImplementation, prepareCallHierarchy, incomingCalls, outgoingCalls.';
    }
  }

  Future<Object?> _sendRequest(String method, Map<String, Object?> params) async {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pendingRequests[id] = completer;

    final message = <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };
    _writeMessage(message);

    return completer.future.timeout(_requestTimeout, onTimeout: () {
      _pendingRequests.remove(id);
      throw TimeoutException('LSP request "$method" timed out after ${_requestTimeout.inSeconds}s');
    });
  }

  void _sendNotification(String method, Map<String, Object?> params) {
    final message = <String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    };
    _writeMessage(message);
  }

  void _writeMessage(Map<String, Object?> message) {
    final body = jsonEncode(message);
    final header = 'Content-Length: ${utf8.encode(body).length}\r\n\r\n';
    _process?.stdin.add(utf8.encode('$header$body'));
  }

  void _onData(String chunk) {
    _responseBuffer.write(chunk);
    _processBuffer();
  }

  void _processBuffer() {
    final data = _responseBuffer.toString();
    var offset = 0;

    while (offset < data.length) {
      final headerEnd = data.indexOf('\r\n\r\n', offset);
      if (headerEnd < 0) break;

      final header = data.substring(offset, headerEnd);
      final lengthMatch = RegExp(r'Content-Length:\s*(\d+)').firstMatch(header);
      if (lengthMatch == null) break;

      final contentLength = int.parse(lengthMatch.group(1)!);
      final bodyStart = headerEnd + 4;
      final bodyEnd = bodyStart + contentLength;

      if (bodyEnd > data.length) break;

      final bodyStr = data.substring(bodyStart, bodyEnd);
      offset = bodyEnd;

      try {
        final msg = jsonDecode(bodyStr);
        if (msg is Map<String, Object?> && msg.containsKey('id')) {
          final id = msg['id'];
          if (id is int && _pendingRequests.containsKey(id)) {
            if (msg.containsKey('error')) {
              final error = msg['error'];
              _pendingRequests.remove(id)!.completeError(
                Exception('LSP error: ${error is Map ? error['message'] : error}'),
              );
            } else {
              _pendingRequests.remove(id)!.complete(msg['result']);
            }
          }
        }
        // Notifications (no id) are silently ignored.
      } catch (_) {
        // Malformed JSON — skip.
      }
    }

    if (offset > 0) {
      _responseBuffer.clear();
      if (offset < data.length) {
        _responseBuffer.write(data.substring(offset));
      }
    }
  }

  Future<void> shutdown() async {
    _idleTimer?.cancel();
    final proc = _process;
    if (proc == null) return;
    _process = null;

    try {
      _writeMessage(<String, Object?>{
        'jsonrpc': '2.0',
        'id': _nextId++,
        'method': 'shutdown',
        'params': null,
      });
      await Future<void>.delayed(const Duration(milliseconds: 200));
      _sendNotification('exit', <String, Object?>{});
      await Future<void>.delayed(const Duration(milliseconds: 100));
    } catch (_) {}

    proc.kill();
    // Complete any pending requests with error
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('LSP session shut down'));
      }
    }
    _pendingRequests.clear();
    _responseBuffer.clear();
  }

  // ── Result formatters ──────────────────────────────────────────

  String _formatLocationResult(Object? result, String label) {
    if (result == null) return '($label: no results)';

    final locations = <Map<String, Object?>>[];
    if (result is List) {
      for (final item in result) {
        if (item is Map<String, Object?>) locations.add(item);
      }
    } else if (result is Map<String, Object?>) {
      locations.add(result);
    }

    if (locations.isEmpty) return '($label: no results)';

    final buffer = StringBuffer('$label (${locations.length} result(s)):\n');
    for (final loc in locations) {
      final uri = loc['uri'] as String? ?? loc['targetUri'] as String? ?? '';
      final range = loc['range'] as Map<String, Object?>? ??
          loc['targetRange'] as Map<String, Object?>? ??
          <String, Object?>{};
      final start = range['start'] as Map<String, Object?>? ?? <String, Object?>{};
      final line = ((start['line'] as int?) ?? 0) + 1;
      final col = ((start['character'] as int?) ?? 0) + 1;
      final path = _uriToPath(uri);
      buffer.writeln('  $path:$line:$col');
    }
    return buffer.toString().trimRight();
  }

  String _formatHoverResult(Object? result) {
    if (result == null) return '(hover: no information at this position)';
    if (result is! Map<String, Object?>) return '(hover: unexpected result format)';

    final contents = result['contents'];
    if (contents == null) return '(hover: no content)';

    if (contents is String) return contents;
    if (contents is Map<String, Object?>) {
      return '${contents['value'] ?? contents['language'] ?? contents}';
    }
    if (contents is List) {
      return contents.map((item) {
        if (item is String) return item;
        if (item is Map<String, Object?>) return item['value'] ?? '$item';
        return '$item';
      }).join('\n');
    }
    return '$contents';
  }

  String _formatSymbolResult(Object? result, String label) {
    if (result == null) return '($label: no results)';
    if (result is! List || result.isEmpty) return '($label: no results)';

    final buffer = StringBuffer('$label (${result.length} symbol(s)):\n');
    for (final item in result) {
      if (item is! Map<String, Object?>) continue;
      final name = item['name'] ?? '?';
      final kind = _symbolKindName(item['kind'] as int? ?? 0);
      final detail = item['detail'] ?? '';
      final loc = item['location'] as Map<String, Object?>?;
      final range = item['range'] as Map<String, Object?>? ??
          loc?['range'] as Map<String, Object?>?;
      final uri = loc?['uri'] as String? ?? '';
      final start = (range?['start'] as Map<String, Object?>?) ?? <String, Object?>{};
      final line = ((start['line'] as int?) ?? 0) + 1;

      final pathStr = uri.isNotEmpty ? '${_uriToPath(uri)}:$line' : 'line $line';
      final detailStr = (detail as String).isNotEmpty ? ' — $detail' : '';
      buffer.writeln('  [$kind] $name$detailStr ($pathStr)');

      // Nested children (DocumentSymbol)
      final children = item['children'] as List?;
      if (children != null) {
        for (final child in children) {
          if (child is! Map<String, Object?>) continue;
          final cName = child['name'] ?? '?';
          final cKind = _symbolKindName(child['kind'] as int? ?? 0);
          final cRange = child['range'] as Map<String, Object?>?;
          final cStart = (cRange?['start'] as Map<String, Object?>?) ?? <String, Object?>{};
          final cLine = ((cStart['line'] as int?) ?? 0) + 1;
          buffer.writeln('    [$cKind] $cName (line $cLine)');
        }
      }
    }
    return buffer.toString().trimRight();
  }

  String _formatCallHierarchyItems(Object? result) {
    if (result == null || result is! List || result.isEmpty) {
      return '(no call hierarchy item found at this position)';
    }
    final buffer = StringBuffer('Call Hierarchy Items:\n');
    for (final item in result) {
      if (item is! Map<String, Object?>) continue;
      final name = item['name'] ?? '?';
      final kind = _symbolKindName(item['kind'] as int? ?? 0);
      final uri = item['uri'] as String? ?? '';
      final range = item['range'] as Map<String, Object?>?;
      final start = (range?['start'] as Map<String, Object?>?) ?? <String, Object?>{};
      final line = ((start['line'] as int?) ?? 0) + 1;
      buffer.writeln('  [$kind] $name (${_uriToPath(uri)}:$line)');
    }
    return buffer.toString().trimRight();
  }

  List<Map<String, Object?>> _parseCallHierarchyItems(Object? result) {
    if (result == null || result is! List) return <Map<String, Object?>>[];
    return result
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
  }

  String _formatCallResults(Object? result, String label) {
    if (result == null || result is! List || result.isEmpty) {
      return '($label: none)';
    }
    final buffer = StringBuffer('$label (${result.length}):\n');
    for (final item in result) {
      if (item is! Map<String, Object?>) continue;
      // 'from' for incoming, 'to' for outgoing
      final target =
          item['from'] as Map<String, Object?>? ?? item['to'] as Map<String, Object?>?;
      if (target == null) continue;
      final name = target['name'] ?? '?';
      final kind = _symbolKindName(target['kind'] as int? ?? 0);
      final uri = target['uri'] as String? ?? '';
      final range = target['range'] as Map<String, Object?>?;
      final start = (range?['start'] as Map<String, Object?>?) ?? <String, Object?>{};
      final line = ((start['line'] as int?) ?? 0) + 1;
      buffer.writeln('  [$kind] $name (${_uriToPath(uri)}:$line)');
    }
    return buffer.toString().trimRight();
  }

  String _uriToPath(String uri) {
    try {
      final parsed = Uri.parse(uri);
      if (parsed.scheme == 'file') return parsed.toFilePath();
      return uri;
    } catch (_) {
      return uri;
    }
  }

  static String _symbolKindName(int kind) {
    const names = <int, String>{
      1: 'File',
      2: 'Module',
      3: 'Namespace',
      4: 'Package',
      5: 'Class',
      6: 'Method',
      7: 'Property',
      8: 'Field',
      9: 'Constructor',
      10: 'Enum',
      11: 'Interface',
      12: 'Function',
      13: 'Variable',
      14: 'Constant',
      15: 'String',
      16: 'Number',
      17: 'Boolean',
      18: 'Array',
      19: 'Object',
      20: 'Key',
      21: 'Null',
      22: 'EnumMember',
      23: 'Struct',
      24: 'Event',
      25: 'Operator',
      26: 'TypeParameter',
    };
    return names[kind] ?? 'Symbol($kind)';
  }
}
