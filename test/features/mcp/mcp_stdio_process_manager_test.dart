import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/service/mcp_stdio_process_manager.dart';

void main() {
  test('parseMcpStdioJsonRpcLine safely parses JSON-RPC object lines', () {
    final parsed = parseMcpStdioJsonRpcLine(
      jsonEncode(<Object?, Object?>{
        'jsonrpc': '2.0',
        'id': 7,
        'result': <Object?, Object?>{
          'serverInfo': <Object?, Object?>{'name': 'demo'},
        },
      }),
    );

    expect(parsed, isNotNull);
    expect(parsed!['id'], 7);
    expect(parsed['result'], isA<Map>());
  });

  test('parseMcpStdioJsonRpcLine rejects malformed or non-object lines', () {
    expect(parseMcpStdioJsonRpcLine('npm notice ready'), isNull);
    expect(parseMcpStdioJsonRpcLine('[1,2,3]'), isNull);
    expect(parseMcpStdioJsonRpcLine('{'), isNull);
    expect(parseMcpStdioJsonRpcLine(''), isNull);
  });
}
