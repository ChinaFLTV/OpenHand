import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() => runFlutterWidgetCheck(
  root: File.fromUri(Platform.script).parent.parent,
  name: 'runtime_lifecycle',
  source: _checks,
);

const _checks = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/ai_session_controller.dart';
import 'package:openhand/features/ai/data/ai_session_store.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_usage_promotion_store.dart';
import 'package:openhand/features/ai/tools/ai_tool_registry.dart';
import 'package:openhand/shared/db/database_service.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';
import 'package:openhand/features/web_reverse/lsp/web_reverse_lsp_client.dart';
import 'package:openhand/shared/net/json_rpc_message.dart';
import 'package:openhand/app/model/hook_config.dart';
import 'package:openhand/features/hooks/hooks_controller.dart';
import 'package:openhand/features/hooks/service/hooks_executor.dart';
import 'package:openhand/app/support/app_runtime_cleanup_registry.dart';
import 'package:openhand/features/web_reverse/web_reverse_cdp_client.dart';

final class _ObservedCancelFuture implements Future<void> {
  _ObservedCancelFuture(this.future);
  final Future<void> future;
  int listeners = 0;
  @override
  Future<R> then<R>(FutureOr<R> Function(void) onValue, {Function? onError}) {
    listeners++;
    return future.then<R>(onValue, onError: onError);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Hooks implements HooksController {
  _Hooks(this.hooks);
  final List<HookEntry> hooks;
  @override
  List<HookEntry> enabledHooksForEvent(HookEvent event) => hooks;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Sink implements StreamSink<dynamic> {
  final ended = Completer<void>();
  Object? sendError;
  @override
  void add(dynamic data) { if (sendError != null) throw sendError!; }
  @override
  Future<void> close() => ended.future;
  @override
  Future<void> get done => ended.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DrainRuntime implements AiToolRuntimeService {
  @override
  final toolRegistry = AiToolRegistry.lightweightOnly();
  @override
  Future<AiResolvedToolCatalog> resolveCatalog({
    required AiSessionRuntimeContext runtimeContext, String? templateId,
  }) async => const AiResolvedToolCatalog(definitions: [], toolsByName: {});
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('低速长响应共享排空时限，35 秒内释放会话且正文与思考完整落库', () async {
    final directory = await Directory.systemTemp.createTemp('openhand_stream_drain_');
    final database = await DatabaseService.initialize(databasePath: '${directory.path}/test.db');
    final store = AiSessionStore(sessionsDirectoryPath: directory.path);
    final usage = AiToolUsagePromotionStore(filePath: '${directory.path}/usage.json');
    final reply = '最终正文：${'甲' * 12000}处理完成。';
    final reasoning = '分析记录：${'乙' * 8000}';
    var requests = 0;
    final requested = Completer<void>();
    final client = AiChatService(client: MockClient((request) async {
      requests++;
      if (!requested.isCompleted) requested.complete();
      return http.Response(
        'data: ${jsonEncode({'choices': [{'index': 0, 'delta': {
          'reasoning_content': reasoning, 'content': reply,
        }}]})}\n\n'
        'data: ${jsonEncode({'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}]})}\n\n'
        'data: [DONE]\n\n',
        200, headers: {'content-type': 'text/event-stream; charset=utf-8'},
      );
    }));
    const sessionId = '流式排空回归';
    final now = DateTime.now().toUtc();
    await store.save(AiSession(
      id: sessionId, title: sessionId, templateId: 'chat', templateName: '对话',
      templateIconName: 'chat', templateInternalVersion: '1',
      createdAt: now, updatedAt: now, environment: AiSessionEnvironment.fromJson({}),
      statistics: const AiSessionStatistics.initial(), recentErrors: [], messages: [],
    ));
    final controller = await AiSessionController.create(
      store: store, chatClient: client, toolRuntimeService: _DrainRuntime(),
      toolUsagePromotionStore: usage,
      templateRepository: AiPromptTemplateRepository(loader: (path) => File(path).readAsString()),
    );
    addTearDown(() async {
      await controller.stopResponding(sessionId);
      await controller.shutdown();
      controller.dispose();
      client.dispose();
      await usage.shutdown();
      await database.close();
      await directory.delete(recursive: true);
    });
    final elapsed = Stopwatch()..start();
    final sending = controller.sendMessage(
      sessionId: sessionId, content: '请返回完整说明。',
      model: const AiModelConfig(
        id: '流式检查', baseUrl: 'https://example.test/v1',
        authScheme: AiAuthScheme.bearer, token: 'test', modelId: 'gpt-4o',
        protocolType: AiProtocolType.openai,
      ),
      runtimeContext: AiSessionRuntimeContext(
        localeTag: 'zh', appVersion: '测试', appBuildNumber: '1',
        settingsFilePath: '', skillsStoragePath: '', mcpServersFilePath: '', userMemoryFilePath: '',
        compressionThresholdChars: 1000000, autoTitleEnabled: false,
        memoryEnabled: false, memoryEntries: [],
        streamMaxCharsPerSecond: 1, streamMaxMessageCardsPerSecond: 0,
      ),
    ).timeout(const Duration(seconds: 35));
    await requested.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(controller.isSending, isTrue, reason: '必须实际经过显示节流，不能绕过排空路径');
    expect(await sending, isTrue, reason: controller.lastErrorMessageForSession(sessionId));
    elapsed.stop();
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 35)));
    expect(elapsed.elapsed, greaterThan(const Duration(seconds: 29)));
    expect(controller.isSending, isFalse);
    expect(requests, 1);
    final saved = (await store.loadSession(sessionId))!;
    expect(saved.messages.where((message) => message.kind == AiSessionMessageKind.assistant).single.content, reply);
    expect(saved.messages.where((message) => message.kind == AiSessionMessageKind.reasoning).single.content, reasoning);
  }, timeout: const Timeout(Duration(seconds: 50)));

  for (final persistent in [false, true]) {
    test('Bash ${persistent ? '持久' : '独立'}命令共享取消监听，成功后不保留逐次回调', () async {
      final service = AiBashToolService();
      final cancel = Completer<void>();
      final observed = _ObservedCancelFuture(cancel.future);
      try {
        for (var index = 0; index < 3; index++) {
          final result = await service.execute(
            command: 'echo 回归检查',
            workingDirectory: Directory.current.path,
            sessionId: persistent ? '取消监听回归' : null,
            denyRules: const [], requireWriteConfirmation: false,
            dangerouslyDisableSandbox: true,
            cancelSignal: observed,
          );
          expect(result.status, BashToolExecutionStatus.success);
        }
        expect(observed.listeners, 1);
        cancel.complete();
        await Future<void>.delayed(Duration.zero);
      } finally {
        await service.shutdown();
      }
    });
  }

  test('Bash 启动前取消不执行命令，运行中取消与超时保留不同终态', () async {
    final service = AiBashToolService();
    final directory = await Directory.systemTemp.createTemp('openhand_bash_cancel_');
    try {
      final marker = File('${directory.path}/marker.txt');
      final beforeLaunch = Completer<void>()..complete();
      final skipped = await service.execute(
        command: 'echo 不应执行 > "${marker.path}"',
        workingDirectory: directory.path,
        denyRules: const [], requireWriteConfirmation: false,
        dangerouslyDisableSandbox: true, cancelSignal: beforeLaunch.future,
      );
      expect(skipped.status, BashToolExecutionStatus.cancelled);
      expect(await marker.exists(), isFalse);
      for (final cancelRunning in [true, false]) {
        final cancel = Completer<void>();
        final result = await service.execute(
          command: Platform.isWindows ? 'ping -n 30 127.0.0.1 > nul' : 'sleep 30',
          workingDirectory: directory.path,
          denyRules: const [], requireWriteConfirmation: false,
          dangerouslyDisableSandbox: true,
          timeoutMs: cancelRunning ? 5000 : 50,
          cancelSignal: cancelRunning ? cancel.future : null,
          onUpdate: (update) {
            if (cancelRunning && !cancel.isCompleted) cancel.complete();
          },
        );
        expect(result.status, cancelRunning ? BashToolExecutionStatus.cancelled : BashToolExecutionStatus.timedOut);
      }
    } finally {
      await service.shutdown();
      await directory.delete(recursive: true);
    }
  });

  test('JSON-RPC 响应保留空结果，拒绝请求、通知和矛盾信封', () {
    expect(isJsonRpcResponse({'jsonrpc': '2.0', 'id': 1, 'result': null}), isTrue);
    expect(isJsonRpcResponse({'jsonrpc': '2.0', 'id': '请求', 'error': {'code': -32601, 'message': '方法不存在'}}), isTrue);
    for (final message in <Map<String, Object?>>[
      {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
      {'jsonrpc': '2.0', 'method': '通知'},
      {'jsonrpc': '2.0', 'id': 1, 'result': null, 'error': {}},
      {'jsonrpc': '2.0', 'id': null, 'error': {}},
      {'jsonrpc': '2.0', 'id': 1},
      {'jsonrpc': '1.0', 'id': 1, 'result': null},
    ]) {
      expect(isJsonRpcResponse(message), isFalse, reason: '$message');
    }
  });

  test('LSP 启动被取消后可以重新握手，重复停止不会遗留请求', () async {
    final client = WebReverseLspClient();
    final args = [File('scripts/support/lsp_server_fixture.dart').absolute.path, 'collision'];
    try {
      final starting = client.start(cmd: 'dart', cmdArgs: args);
      final joining = client.start(cmd: 'dart', cmdArgs: args);
      await client.stop();
      expect(await starting, isFalse);
      expect(await joining, isFalse);
      expect(await client.start(cmd: 'dart', cmdArgs: args), isTrue);
      expect(await client.hover('file:///检查.dart', 0, 0), '正确结果');
      await Future.wait([client.stop(), client.stop()]);
      expect(client.status, WebReverseLspStatus.idle);
      expect(await client.hover('file:///检查.dart', 0, 0), isNull);
    } finally {
      await client.stop();
    }
  });

  test('MCP 标准输入输出响应不被反向请求抢占', () async {
    final service = DefaultMcpToolDiscoveryService();
    try {
      final catalog = await service.discoverTools(McpServer(
        name: '标准输入输出协议检查', type: McpServerType.stdio, enabled: true,
        command: 'dart', args: [File('scripts/support/lsp_server_fixture.dart').absolute.path, 'mcp'],
      ));
      expect(catalog.tools.map((tool) => tool.name), ['检查工具']);
    } finally {
      service.dispose();
    }
  });

  for (final mode in ['collision', 'fractional', 'header']) {
    test('LSP 正确隔离响应与消息头边界：$mode', () async {
      final client = WebReverseLspClient();
      try {
        final started = await client.start(cmd: 'dart', cmdArgs: [
          File('scripts/support/lsp_server_fixture.dart').absolute.path, mode,
        ]);
        if (mode == 'header') {
          expect(started, isFalse);
          expect(client.lastError, contains('消息头超过'));
        } else {
          expect(started, isTrue);
          expect(await client.hover('file:///检查.dart', 0, 0), '正确结果');
        }
      } finally {
        await client.stop();
      }
      expect(client.status, WebReverseLspStatus.idle);
    });
  }

  for (final sse in [false, true]) {
    test('MCP ${sse ? 'SSE' : 'JSON'} 响应不能被同编号服务端请求抢占', () async {
      final httpClient = MockClient((request) async {
        if (request.method == 'DELETE') return http.Response('', 204);
        final payload = jsonDecode(request.body) as Map;
        if (!payload.containsKey('id')) return http.Response('', 202);
        final messages = [
          {'jsonrpc': '2.0', 'id': payload['id'], 'method': 'ping'},
          {'jsonrpc': '2.0', 'id': payload['id'], 'result': payload['method'] == 'initialize'
            ? {'protocolVersion': '2025-03-26', 'capabilities': {'tools': {}}}
            : {'tools': [{'name': '检查工具', 'inputSchema': {'type': 'object'}}]}},
        ];
        return http.Response(sse
          ? messages.map((message) => 'data: ${jsonEncode(message)}\n\n').join()
          : jsonEncode(messages), 200,
          headers: {'content-type': sse ? 'text/event-stream; charset=utf-8' : 'application/json'});
      });
      final service = DefaultMcpToolDiscoveryService(client: httpClient);
      try {
        final catalog = await service.discoverTools(const McpServer(
          name: '协议检查', type: McpServerType.streamableHttp,
          enabled: true, url: 'https://example.test/mcp',
        ));
        expect(catalog.tools.map((tool) => tool.name), ['检查工具']);
      } finally {
        service.dispose();
        httpClient.close();
      }
    });
  }

  test('钩子逐项结果保留顺序、失败信息和拦截语义', () async {
    final hooks = [for (final code in [0, 1, 2, 0]) HookEntry(
      id: '回归-$code', event: HookEvent.preToolUse, label: '回归-$code',
      scriptContent: Platform.isWindows ? 'exit /b $code' : 'exit $code',
    )];
    final executor = HooksExecutor(controller: _Hooks(hooks));
    final recorded = <HookUsageRecord>[];
    executor.configureUsageRecorder((_, records) async => recorded.addAll(records));
    final results = await executor.executeEvent(event: HookEvent.preToolUse, sessionId: '生命周期清理回归');
    expect(results.map((result) => result.status), [kHookStatusSuccess, kHookStatusFailed, kHookStatusBlocked]);
    expect(recorded.map((record) => record.status), results.map((result) => result.status));
    expect(recorded.map((record) => record.hookId), ['回归-0', '回归-1', '回归-2']);
  });

  test('关闭立即终止待响应命令，不等待传输清理', () async {
    final sink = _Sink();
    final events = StreamController<dynamic>();
    var connections = 0;
    final client = WebReverseCdpClient(
      endpoint: 'ws://localhost:9222',
      connector: (_) {
        connections++;
        return WebReverseCdpTransport(ready: Future.value(), stream: events.stream, sink: sink);
      },
    );
    final connecting = client.connect();
    expect(identical(connecting, client.connect()), isTrue);
    await connecting;
    expect(connections, 1);
    final pending = client.send('Page.enable');
    final rejected = expectLater(pending.timeout(const Duration(milliseconds: 100)), throwsStateError);
    final closing = client.close();
    expect(identical(closing, client.close()), isTrue);
    try {
      await rejected;
    } finally {
      sink.ended.complete();
      await closing;
      await events.close();
    }
  });

  test('同步发送失败只交给调用方，不产生孤立 Future 错误', () async {
    final sink = _Sink()..sendError = StateError('传输已关闭');
    final events = StreamController<dynamic>();
    final client = WebReverseCdpClient(
      endpoint: 'ws://localhost:9222',
      connector: (_) => WebReverseCdpTransport(ready: Future.value(), stream: events.stream, sink: sink),
    );
    await client.connect();
    await expectLater(client.send('Page.enable'), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    sink.ended.complete();
    await client.close();
    await events.close();
  });

  test('连接失败后允许重试，关闭后拒绝再次连接', () async {
    final sink = _Sink();
    final events = StreamController<dynamic>();
    var attempts = 0;
    final client = WebReverseCdpClient(
      endpoint: 'ws://localhost:9222',
      connector: (_) {
        if (++attempts == 1) throw StateError('连接失败');
        return WebReverseCdpTransport(ready: Future.value(), stream: events.stream, sink: sink);
      },
    );
    await expectLater(client.connect(), throwsStateError);
    await client.connect();
    expect(attempts, 2);
    expect(client.canSendCommands, isTrue);
    sink.ended.complete();
    await client.close();
    await expectLater(client.connect(), throwsStateError);
    await events.close();
  });

  test('资源注册表逆序清理且同步重入共享完成信号', () async {
    final registry = AppRuntimeCleanupRegistry();
    final order = <int>[];
    Future<void>? nested;
    registry.register('先注册', () => order.add(1));
    registry.register('后注册', () {
      nested = registry.dispose();
      expect(() => registry.register('迟到注册', () {}), throwsStateError);
      order.add(2);
    });
    final closing = registry.dispose();
    await closing;
    expect(identical(closing, nested), isTrue);
    expect(identical(closing, registry.dispose()), isTrue);
    expect(order, [2, 1]);
  });
}
''';
