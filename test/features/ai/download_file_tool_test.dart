import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openhand/features/ai/model/ai_attachment.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_builtin_tool_lazy_loading_applier.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/web/ai_download_file_tool.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('openhand-download-');
  });
  tearDown(() async => directory.delete(recursive: true));

  AiToolExecutionContext context({
    Map<String, Object?> arguments = const {},
    Future<void>? cancelSignal,
    void Function(BashToolExecutionUpdate)? onUpdate,
  }) => AiToolExecutionContext(
    sessionId: 'session',
    catalog: const AiResolvedToolCatalog(definitions: [], toolsByName: {}),
    toolCall: const AiToolCall(id: '调用', name: 'DownloadFile', arguments: '{}'),
    decodedArguments: {'url': 'https://files.example/photo', ...arguments},
    model: AiModelConfig.fromJson({}),
    previouslyReadFiles: {},
    denyCommandRules: [],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
    cancelSignal: cancelSignal,
    onBashUpdate: onUpdate,
  );

  AiDownloadFileTool tool(http.Client client, {Duration? timeout}) {
    addTearDown(client.close);
    return AiDownloadFileTool(
      httpClient: client,
      hostLookup: (_) async => [InternetAddress('8.8.8.8')],
      directoryProvider: (_) => directory.path,
      timeout: timeout ?? const Duration(seconds: 5),
    );
  }

  AiMessageAttachment resultAttachment(AiToolExecutionResult result) =>
      AiMessageAttachment.fromJson(
        (jsonDecode(result.resultText) as Map)['文件'],
      );

  test('下载保留原始字节和中文文件名，并生成可交付附件及进度', () async {
    final bytes = [137, 80, 78, 71, 0, 255];
    final updates = <BashToolExecutionUpdate>[];
    final result = await tool(
      MockClient(
        (_) async => http.Response.bytes(
          bytes,
          200,
          headers: {
            'content-type': 'IMAGE/PNG ; charset=binary',
            'content-disposition':
                "attachment; filename*=UTF-8''${Uri.encodeComponent('写真.png')}",
          },
        ),
      ),
    ).execute(context(onUpdate: updates.add));
    expect(result.status, BashToolExecutionStatus.success);
    final attachment = resultAttachment(result);
    expect(attachment.name, '写真.png');
    expect(attachment.kind, AiAttachmentKind.image);
    expect(await File(attachment.storagePath).readAsBytes(), bytes);
    expect(result.metadata[aiSessionDownloadedFilesMetadataKey], hasLength(1));
    expect(updates, isNotEmpty);
  });

  test('并发同名下载互不覆盖，文件名不可逃逸，中间资料不自动交付', () async {
    final downloader = tool(
      MockClient((_) async => http.Response.bytes(utf8.encode('内容'), 200)),
    );
    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        downloader.execute(
          context(
            arguments: {'filename': '../../写真.txt', 'attach_to_reply': false},
          ),
        ),
    ]);
    final attachments = results.map(resultAttachment).toList();
    expect(attachments.map((a) => a.storagePath).toSet(), hasLength(2));
    for (final attachment in attachments) {
      expect(p.isWithin(directory.path, attachment.storagePath), isTrue);
      expect(attachment.name.contains('/'), isFalse);
    }
    expect(results.every((result) => result.metadata.isEmpty), isTrue);
  });

  test('逐跳校验地址，拒绝内网、非 HTTP 和无限重定向', () async {
    var requests = 0;
    final downloader = tool(
      MockClient((request) async {
        requests++;
        return http.Response(
          '',
          302,
          headers: {
            'location': request.url.path == '/loop'
                ? '/loop'
                : 'http://127.0.0.1/private',
          },
        );
      }),
    );
    for (final url in [
      'file:///etc/passwd',
      'http://127.0.0.1/file',
      'https://files.example/photo',
    ]) {
      final result = await downloader.execute(context(arguments: {'url': url}));
      expect(result.status, isNot(BashToolExecutionStatus.success));
    }
    expect(requests, 1);
    final loop = await downloader.execute(
      context(arguments: {'url': 'https://files.example/loop'}),
    );
    expect(loop.stderr, contains('重定向超过'));
    expect(requests, AiDownloadFileTool.maxRedirects + 2);
    expect(await directory.list().toList(), isEmpty);
  });

  test('拒绝网页、错误响应、空文件、过大声明和不完整文件，清理残留', () async {
    final cases = <http.StreamedResponse Function()>[
      () => http.StreamedResponse(Stream.value([1]), 404),
      () => http.StreamedResponse(
        Stream.value([1]),
        200,
        headers: {'content-type': 'text/html'},
      ),
      () => http.StreamedResponse(const Stream.empty(), 200),
      () => http.StreamedResponse(
        Stream.value([1]),
        200,
        contentLength: AiDownloadFileTool.maxBytes + 1,
      ),
      () => http.StreamedResponse(Stream.value([1]), 200, contentLength: 4),
      () => http.StreamedResponse(Stream.value(_OversizedChunk()), 200),
      () => http.StreamedResponse(
        Stream.error(const SocketException('连接中断')),
        200,
      ),
    ];
    for (final response in cases) {
      final result = await tool(
        MockClient.streaming((_, _) async => response()),
      ).execute(context());
      expect(result.status, BashToolExecutionStatus.failed);
      expect(result.metadata, isEmpty);
      expect(await directory.list().toList(), isEmpty);
    }
  });

  test('取消及总超时中止响应流，并删除已写入的半文件', () async {
    for (final cancel in [true, false]) {
      final cancellation = Completer<void>();
      final client = _InterruptibleClient();
      final downloader = tool(
        client,
        timeout: const Duration(milliseconds: 150),
      );
      final future = downloader.execute(
        context(
          cancelSignal: cancellation.future,
          onUpdate: (_) {
            if (cancel && !cancellation.isCompleted) cancellation.complete();
          },
        ),
      );
      final result = await future;
      expect(
        result.status,
        cancel
            ? BashToolExecutionStatus.cancelled
            : BashToolExecutionStatus.timedOut,
      );
      expect(client.aborted, isTrue);
      expect(await directory.list().toList(), isEmpty);
    }
  });

  test('默认懒加载，工具目录保留下载工具供 ToolSearch 发现', () {
    const kind = AiBuiltinToolKind.downloadFile;
    expect(
      AiBuiltinToolConfig.defaultLoadStrategyForKind(kind),
      AiBuiltinToolLoadStrategy.lazy,
    );
    expect(AiBuiltinToolConfig.defaultForceLoadForKind(kind), isFalse);
    final download = AiToolRuntimeService.builtinToolDefault(kind)!;
    final search = AiToolRuntimeService.builtinToolDefault(
      AiBuiltinToolKind.toolSearch,
    )!;
    final catalog = AiResolvedToolCatalog(
      definitions: [download.definition, search.definition],
      toolsByName: {download.name: download, search.name: search},
    );
    final deferred = AiBuiltinToolLazyLoadingApplier.apply(
      catalog: catalog,
      sourceCatalog: catalog,
      mode: AiBuiltinToolLazyLoadingMode.enabled,
      thresholdTokens: 8000,
      charsPerToken: 4,
    );
    expect(deferred.find(download.name), isNull);
    expect(deferred.findDeferredTool(download.name)?.builtinKind, kind);
  });

  test('最终回复仅汇总本轮成功附件，去除重复、失败与已删除结果', () {
    final attachment = AiMessageAttachment(
      id: '附件',
      name: '写真 (1).png',
      storagePath: '/tmp/写真 (1).png',
      kind: AiAttachmentKind.image,
      mimeType: 'image/png',
      sizeBytes: 10,
    );
    AiSessionMessage user(String id) => AiSessionMessage.user(
      id: id,
      content: '下载',
      createdAt: DateTime.utc(2026),
    );
    AiSessionMessage result(String id, {String status = 'success'}) =>
        AiSessionMessage.toolResult(
          id: id,
          content: '完成',
          createdAt: DateTime.utc(2026),
          metadata: {
            'status': status,
            aiSessionDownloadedFilesMetadataKey:
                AiMessageAttachment.listToMetadata([attachment]),
          },
        );
    expect(
      collectAiDownloadedReplyAttachments([
        user('旧轮'),
        result('旧结果'),
        user('本轮'),
      ]),
      isEmpty,
    );
    expect(
      collectAiDownloadedReplyAttachments([
        user('本轮'),
        result('失败', status: 'failed'),
        result('已删除').copyWith(isDeleted: true),
      ]),
      isEmpty,
    );
    expect(
      collectAiDownloadedReplyAttachments([
        user('本轮'),
        result('成功'),
        result('重复'),
      ]),
      hasLength(1),
    );
    for (final link in [
      '![写真](${attachment.storagePath})',
      '[下载](<${attachment.storagePath}> "原图")',
      '![写真](${Uri.file(attachment.storagePath)})',
      '<img src="${attachment.storagePath}" />',
    ]) {
      expect(stripAiReplyAttachmentLinks(link, [attachment]), isEmpty);
    }
    const source = '[来源](https://files.example/photo)';
    expect(stripAiReplyAttachmentLinks(source, [attachment]), source);
  });
}

class _InterruptibleClient extends http.BaseClient {
  bool aborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = StreamController<List<int>>();
    unawaited(
      (request as http.AbortableRequest).abortTrigger!.then((_) async {
        aborted = true;
        stream.addError(http.RequestAbortedException(request.url));
        await stream.close();
      }),
    );
    stream.add([1, 2, 3]);
    return http.StreamedResponse(stream.stream, 200);
  }
}

class _OversizedChunk extends ListBase<int> {
  @override
  int get length => AiDownloadFileTool.maxBytes + 1;
  @override
  set length(int value) => throw UnsupportedError('测试字节流只读');
  @override
  int operator [](int index) => throw StateError('超限字节流不应被读取');
  @override
  void operator []=(int index, int value) => throw UnsupportedError('测试字节流只读');
}
