import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/support/openhand_paths.dart';
import 'package:openhand/features/mcp/model/mcp_server_ops.dart';
import 'package:openhand/features/mcp/service/mcp_server_ops_runtime.dart';
import 'package:path/path.dart' as p;

void main() {
  group('MCP 运维工作区', () {
    late Directory temporaryDirectory;
    late Directory workspace;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'openhand-mcp-workspace-',
      );
      workspace = await Directory(
        p.join(temporaryDirectory.path, 'workspace'),
      ).create();
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('相对路径按配置工作区解析并传给工具', () async {
      Map<String, Object?>? invokedArguments;
      String? invocationWorkspaceRoot;

      final response = await _callScopedTool(
        workspaceRoot: workspace.path,
        arguments: const <String, Object?>{'path': 'nested'},
        onInvoke: (arguments, context) {
          invokedArguments = arguments;
          invocationWorkspaceRoot = context.workspaceRoot;
        },
      );

      expect(response['result'], isA<Map>());
      expect(invokedArguments?['path'], p.join(workspace.path, 'nested'));
      expect(invocationWorkspaceRoot, p.normalize(workspace.path));
    });

    test('工作区根目录可用点号表示', () async {
      Map<String, Object?>? invokedArguments;

      final response = await _callScopedTool(
        workspaceRoot: workspace.path,
        arguments: const <String, Object?>{'path': '.'},
        onInvoke: (arguments, _) => invokedArguments = arguments,
      );

      expect(response['result'], isA<Map>());
      expect(invokedArguments?['path'], p.normalize(workspace.path));
    });

    test('波浪号路径展开到用户目录', () async {
      Map<String, Object?>? invokedArguments;
      final home = OpenHandPaths.homeDirectoryPath();

      final response = await _callScopedTool(
        workspaceRoot: home,
        arguments: const <String, Object?>{'path': '~/Downloads'},
        onInvoke: (arguments, _) => invokedArguments = arguments,
      );

      expect(response['result'], isA<Map>());
      expect(invokedArguments?['path'], p.join(home, 'Downloads'));
    });

    test('文件匹配模式不参与路径判界', () async {
      Map<String, Object?>? invokedArguments;

      final response = await _callScopedTool(
        workspaceRoot: workspace.path,
        arguments: const <String, Object?>{'file_pattern': '*.dart'},
        onInvoke: (arguments, _) => invokedArguments = arguments,
      );

      expect(response['result'], isA<Map>());
      expect(invokedArguments?['file_pattern'], '*.dart');
    });

    test('拒绝工作区外的绝对路径', () async {
      var invoked = false;

      final response = await _callScopedTool(
        workspaceRoot: workspace.path,
        arguments: <String, Object?>{'path': temporaryDirectory.path},
        onInvoke: (_, _) => invoked = true,
      );

      expect(_jsonRpcErrorCode(response), -32006);
      expect(invoked, isFalse);
    });

    test('拒绝通过符号链接逃逸工作区', () async {
      final outside = await Directory(
        p.join(temporaryDirectory.path, 'outside'),
      ).create();
      final escape = Link(p.join(workspace.path, 'escape'));
      await escape.create(outside.path);
      var invoked = false;

      final response = await _callScopedTool(
        workspaceRoot: workspace.path,
        arguments: <String, Object?>{
          'file_path': p.join(escape.path, 'new.txt'),
        },
        onInvoke: (_, _) => invoked = true,
      );

      expect(_jsonRpcErrorCode(response), -32006);
      expect(invoked, isFalse);
    }, skip: Platform.isWindows ? 'Windows 创建符号链接需要额外权限。' : false);

    test('初始化说明包含配置工作区', () async {
      final response = await _sendRequest(
        workspaceRoot: workspace.path,
        method: 'initialize',
      );
      final result = response['result'] as Map;

      expect(result['instructions'], contains(p.normalize(workspace.path)));
      expect(result['instructions'], contains('relative paths'));
    });
  });
}

Future<Map<String, Object?>> _callScopedTool({
  required String workspaceRoot,
  required Map<String, Object?> arguments,
  required void Function(
    Map<String, Object?> arguments,
    McpOpsToolInvocationContext context,
  )
  onInvoke,
}) {
  return _sendRequest(
    workspaceRoot: workspaceRoot,
    method: 'tools/call',
    params: <String, Object?>{'name': 'scoped_tool', 'arguments': arguments},
    onInvoke: onInvoke,
  );
}

Future<Map<String, Object?>> _sendRequest({
  required String workspaceRoot,
  required String method,
  Map<String, Object?> params = const <String, Object?>{},
  void Function(
    Map<String, Object?> arguments,
    McpOpsToolInvocationContext context,
  )?
  onInvoke,
}) async {
  final runtime = McpServerOpsRuntime(
    toolListProvider: () => const <McpOpsToolDefinition>[
      McpOpsToolDefinition(
        name: 'scoped_tool',
        title: '工作区工具',
        description: '验证工作区路径。',
        surface: McpOpsExposureSurface.builtinTools,
        itemId: 'scoped',
        endpointId: 'invoke',
        inputSchema: <String, Object?>{'type': 'object'},
      ),
    ],
    toolInvoker: (_, arguments, context) async {
      onInvoke?.call(arguments, context);
      return const McpOpsToolInvocationResult(text: 'ok');
    },
    approvalGate: (_) async => true,
    auditSink: (_) {},
    snapshotSink: (_) {},
  );
  await runtime.start(
    McpOpsConfig(listenPort: 0, workspaceRoot: workspaceRoot),
  );
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${runtime.snapshot.boundPort}/mcp'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        if (params.isNotEmpty) 'params': params,
      }),
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    expect(response.statusCode, HttpStatus.ok);
    return Map<String, Object?>.from(jsonDecode(body) as Map);
  } finally {
    client.close(force: true);
    await runtime.stop();
  }
}

int? _jsonRpcErrorCode(Map<String, Object?> response) {
  final error = response['error'];
  return error is Map ? error['code'] as int? : null;
}
