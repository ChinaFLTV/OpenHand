import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_tool_execution_registry.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

void main() {
  test('stdio tool cancellation closes session idempotently', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'openhand_mcp_stdio_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final script = File('${tempDir.path}/fake_mcp_server.dart');
    await script.writeAsString(_fakeMcpServerScript);

    const toolCallId = 'mcp-stdio-cancel-test';
    final registry = AiToolExecutionRegistry.instance;
    registry.register(
      toolCallId: toolCallId,
      sessionId: 'test-session',
      kind: AiToolExecutionKind.mcp,
      displayName: 'fake stdio',
    );
    addTearDown(() => registry.unregister(toolCallId));

    final service = DefaultMcpToolDiscoveryService();
    addTearDown(service.dispose);
    final callFuture = service.callTool(
      server: McpServer(
        name: 'fake-stdio',
        type: McpServerType.stdio,
        enabled: true,
        command: _dartExecutable(),
        args: <String>[script.path],
      ),
      toolName: 'hang',
      toolCallId: toolCallId,
    );

    await _waitUntil(
      () => registry.recordOf(toolCallId)?.pid != null,
      timeout: const Duration(seconds: 5),
    );
    await registry.cancelToolCall(toolCallId);

    await expectLater(
      callFuture.timeout(const Duration(seconds: 5)),
      throwsA(isA<McpToolDiscoveryException>()),
    );
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('Timed out waiting for condition.');
}

String _dartExecutable() {
  final separator = Platform.isWindows ? r'\' : '/';
  final executableName = Platform.resolvedExecutable
      .split(separator)
      .last
      .toLowerCase();
  if (executableName == 'dart' || executableName == 'dart.exe') {
    return Platform.resolvedExecutable;
  }
  final result = Process.runSync(Platform.isWindows ? 'where' : 'which', [
    'dart',
  ]);
  if (result.exitCode == 0) {
    final firstLine = '${result.stdout}'.trim().split(RegExp(r'\r?\n')).first;
    if (firstLine.isNotEmpty) {
      return firstLine;
    }
  }
  fail('Unable to resolve dart executable for fake MCP server.');
}

const _fakeMcpServerScript = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

final _buffer = <int>[];

Future<void> main() async {
  await for (final chunk in stdin) {
    _buffer.addAll(chunk);
    _drainMessages();
  }
}

void _drainMessages() {
  while (true) {
    final headerEnd = _findHeaderEnd();
    if (headerEnd < 0) return;
    final separatorLength = _separatorLength(headerEnd);
    final header = ascii.decode(_buffer.sublist(0, headerEnd));
    final length = _contentLength(header);
    if (length == null) {
      _buffer.removeRange(0, headerEnd + separatorLength);
      continue;
    }
    final bodyStart = headerEnd + separatorLength;
    final bodyEnd = bodyStart + length;
    if (_buffer.length < bodyEnd) return;
    final body = utf8.decode(_buffer.sublist(bodyStart, bodyEnd));
    _buffer.removeRange(0, bodyEnd);
    final message = jsonDecode(body) as Map<String, dynamic>;
    _handleMessage(message);
  }
}

void _handleMessage(Map<String, dynamic> message) {
  switch (message['method']) {
    case 'initialize':
      _writeMessage({
        'jsonrpc': '2.0',
        'id': message['id'],
        'result': {
          'protocolVersion': '2025-11-25',
          'capabilities': {},
          'serverInfo': {'name': 'fake', 'version': '1.0.0'},
        },
      });
      return;
    case 'tools/call':
      Timer.periodic(const Duration(seconds: 30), (_) {});
      return;
  }
}

void _writeMessage(Map<String, Object?> message) {
  final body = utf8.encode(jsonEncode(message));
  stdout.add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'));
  stdout.add(body);
}

int _findHeaderEnd() {
  for (var i = 0; i < _buffer.length - 1; i++) {
    if (_buffer[i] == 13 &&
        _buffer[i + 1] == 10 &&
        i + 3 < _buffer.length &&
        _buffer[i + 2] == 13 &&
        _buffer[i + 3] == 10) {
      return i;
    }
    if (_buffer[i] == 10 && _buffer[i + 1] == 10) {
      return i;
    }
  }
  return -1;
}

int _separatorLength(int headerEnd) {
  if (headerEnd + 3 < _buffer.length &&
      _buffer[headerEnd] == 13 &&
      _buffer[headerEnd + 1] == 10 &&
      _buffer[headerEnd + 2] == 13 &&
      _buffer[headerEnd + 3] == 10) {
    return 4;
  }
  return 2;
}

int? _contentLength(String header) {
  for (final line in header.split(RegExp(r'\r?\n'))) {
    final index = line.indexOf(':');
    if (index < 0) continue;
    if (line.substring(0, index).trim().toLowerCase() != 'content-length') {
      continue;
    }
    return int.tryParse(line.substring(index + 1).trim());
  }
  return null;
}
''';
