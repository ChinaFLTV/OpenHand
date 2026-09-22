import 'dart:convert';
import 'dart:io';

/// 通过真实标准输入输出复现双向请求与分帧边界。
Future<void> main(List<String> args) async {
  final mode = args.single;
  if (mode == 'mcp') {
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final request = jsonDecode(line) as Map;
      if (!request.containsKey('id')) continue;
      stdout.writeln(
        jsonEncode({'jsonrpc': '2.0', 'id': request['id'], 'method': 'ping'}),
      );
      stdout.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': request['id'],
          'result': request['method'] == 'initialize'
              ? {
                  'protocolVersion': '2024-11-05',
                  'capabilities': {'tools': {}},
                }
              : {
                  'tools': [
                    {
                      'name': '检查工具',
                      'inputSchema': {'type': 'object'},
                    },
                  ],
                },
        }),
      );
      await stdout.flush();
    }
    return;
  }
  final buffer = <int>[];
  await for (final chunk in stdin) {
    buffer.addAll(chunk);
    while (true) {
      final text = latin1.decode(buffer);
      final separator = text.indexOf('\r\n\r\n');
      if (separator < 0) break;
      final length = int.parse(text.substring(16, separator));
      final end = separator + 4 + length;
      if (buffer.length < end) break;
      final request =
          jsonDecode(utf8.decode(buffer.sublist(separator + 4, end))) as Map;
      buffer.removeRange(0, end);
      if (!request.containsKey('method') || !request.containsKey('id')) {
        continue;
      }
      final id = request['id'] as int;
      final initializing = request['method'] == 'initialize';
      if (!initializing) {
        if (mode == 'collision') {
          _send({
            'jsonrpc': '2.0',
            'id': id,
            'method': 'workspace/configuration',
            'params': {},
          });
        } else if (mode == 'fractional') {
          _send({
            'jsonrpc': '2.0',
            'id': id + 0.5,
            'result': {'contents': '错误结果'},
          });
        }
      }
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'result': initializing ? {'capabilities': {}} : {'contents': '正确结果'},
      }, oversizedHeader: mode == 'header');
      await stdout.flush();
    }
  }
}

void _send(Map<String, Object?> message, {bool oversizedHeader = false}) {
  final body = utf8.encode(jsonEncode(message));
  var header = 'Content-Length: ${body.length}';
  if (oversizedHeader) {
    header += '\r\nX-Padding: ${'a' * (65537 - header.length - 13)}';
  }
  stdout.add([...ascii.encode('$header\r\n\r\n'), ...body]);
}
