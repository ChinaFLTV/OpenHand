import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:openhand/features/skills/data/skillhub_skill_mapper.dart';
import 'package:openhand/shared/net/abortable_http_request.dart';
import 'package:openhand/shared/net/bounded_http_request.dart';
import 'package:openhand/shared/net/http_response_utils.dart';
import 'package:openhand/shared/net/http_status_utils.dart';
import 'package:openhand/shared/net/loopback_hosts.dart';
import 'package:openhand/shared/net/sse_line_parsing.dart';
import 'package:openhand/shared/util/async_concurrency.dart';
import 'package:openhand/shared/util/bounded_file_io.dart';
import 'package:openhand/shared/util/bounded_json_conversion.dart';
import 'package:openhand/shared/util/bounded_text_buffer.dart';
import 'package:openhand/shared/util/date_time_format.dart';
import 'package:openhand/shared/util/duration_bounds.dart';
import 'package:openhand/shared/util/exponential_backoff.dart';
import 'package:openhand/shared/util/hex_encoding.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';
import 'package:openhand/shared/util/lifecycle_cache.dart';
import 'package:openhand/shared/util/message_frame_scan.dart';
import 'package:openhand/shared/util/path_safety.dart';
import 'package:openhand/shared/util/platform_environment.dart';
import 'package:openhand/shared/util/platform_shell.dart';
import 'package:openhand/shared/util/sensitive_data.dart';
import 'package:openhand/shared/util/storage_identifier.dart';
import 'package:openhand/shared/util/text_clip.dart';
import 'package:openhand/shared/util/text_search.dart';
import 'package:openhand/shared/util/transcript_list_windowing.dart';
import 'package:openhand/shared/util/xml_escape.dart';

/// 直接驱动抽出的共享实现：代表输入进、真实返回值出。
Future<void> main() async {
  var failures = 0;
  failures += _checkSkillMarketMapping();
  failures += _checkJsonDecode();
  failures += _checkJsonEncodeFallback();
  failures += _checkJsonMapKeyCollision();
  failures += _checkContentLength();
  failures += _checkBackoff();
  failures += _checkDurationBounds();
  failures += _checkIntegerValueRange();
  failures += _checkPrettyJsonIfDecodable();
  failures += _checkLoopback();
  failures += _checkStringFromValue();
  failures += _checkFiniteNumberParsing();
  failures += _checkGrowableStringKeyedMap();
  failures += _checkHttpRetryableStatus();
  failures += _checkRgbHex();
  failures += _checkXmlEscape();
  failures += _checkCompactDuration();
  failures += _checkCalendarDateMath();
  failures += _checkCanonicalDateTime();
  failures += _checkTextClip();
  failures += _checkPortableFileNameSanitization();
  failures += _checkPlatformShell();
  failures += _checkPlatformEnvironment();
  failures += _checkTextSearch();
  failures += _checkTranscriptHistory();
  failures += _checkBoundedTextBuffer();
  failures += _checkLifecycleCache();
  failures += _checkSensitiveTextRedaction();
  failures += _checkSseFraming();
  failures += await _checkBatchSubscriptionCancellation();
  failures += await _checkAbortableResponseLifetime();
  failures += await _checkHttpCancellation();
  failures += await _checkLateNativeHttpResponse();
  failures += await _checkBoundedByteStreams();
  failures += await _checkSynchronousBoundedFileRead();
  failures += await _checkTemporaryByteStreamWrite();
  failures += await _checkTemporaryDirectoryLifecycle();
  if (failures > 0) {
    stderr.writeln('[共享辅助检查] 失败 $failures 项。');
    exit(1);
  }
  stdout.writeln('[共享辅助检查] 通过。');
}

int _checkSseFraming() {
  const source =
      '\uFEFFevent: 更新\r\ndata: {"正文":\r\ndata: "你好"}\r\n\r\n'
      ': 心跳\r\rdata:  保留空白  \ndata\n\ndata: 末尾';
  const expected =
      'event: 更新\ndata: {"正文":\ndata: "你好"}|: 心跳|'
      'data:  保留空白  \ndata|data: 末尾';
  for (var size = 1; size <= source.length; size++) {
    final buffer = BoundedSseEventBuffer(maxEventCharacters: source.length);
    final blocks = <String>[];
    for (var start = 0; start < source.length; start += size) {
      if (!buffer.add(
        source.substring(start, (start + size).clamp(0, source.length)),
        onEvent: blocks.add,
        isComplete: () => false,
      )) {
        stderr.writeln('SSE 正常分片被错误拒绝');
        return 1;
      }
    }
    buffer.finish(blocks.add);
    if (blocks.join('|') != expected) {
      stderr.writeln('SSE 在分片长度 $size 时错误拆分了事件');
      return 1;
    }
  }
  if (extractSseDataLines('data:  空白  \r\ndata\rdata:\n').join('|') !=
          ' 空白  ||' ||
      sseEventName('event:  更新 ') != ' 更新 ' ||
      sseDataPayload(' data: 忽略') != null) {
    stderr.writeln('SSE 字段解析错误裁剪了载荷或接受了无效字段');
    return 1;
  }
  final bounded = BoundedSseEventBuffer(maxEventCharacters: 7);
  final blocks = <String>[];
  if (!bounded.add('data: 1\r', onEvent: blocks.add, isComplete: () => false) ||
      !bounded.add('\n\r\n', onEvent: blocks.add, isComplete: () => false) ||
      blocks.single != 'data: 1' ||
      bounded.add('data: 12', onEvent: blocks.add, isComplete: () => false)) {
    stderr.writeln('SSE 单事件容量边界处理错误');
    return 1;
  }
  bounded.finish(blocks.add);
  if (blocks.length != 1) {
    stderr.writeln('SSE 超限后不应输出截断事件');
    return 1;
  }
  final stopped = BoundedSseEventBuffer(maxEventCharacters: 12);
  blocks.clear();
  if (!stopped.add(
    'data: [DONE]\n\n${'x' * 100}',
    onEvent: blocks.add,
    isComplete: () => blocks.isNotEmpty,
  )) {
    stderr.writeln('SSE 结束后不应继续解析或保留后续分片');
    return 1;
  }
  stopped.finish(blocks.add);
  if (blocks.length != 1) {
    stderr.writeln('SSE 结束后重复输出了事件');
    return 1;
  }
  return 0;
}

Future<int> _checkBoundedByteStreams() async {
  const idleTimeout = Duration(milliseconds: 30);
  Stream<List<int>> emptyChunks() async* {
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      yield const <int>[];
    }
  }

  try {
    await readBoundedByteStream(
      emptyChunks(),
      maxBytes: 1,
      idleTimeout: idleTimeout,
      totalTimeout: const Duration(seconds: 1),
    );
    stderr.writeln('空数据块不应阻止字节流空闲超时');
    return 1;
  } on TimeoutException catch (error) {
    if (error.duration != idleTimeout) {
      stderr.writeln('空数据块错误地刷新了字节流空闲时限');
      return 1;
    }
  }

  final chunks = await limitByteStream(
    Stream<List<int>>.fromIterable(const <List<int>>[
      <int>[],
      <int>[1],
      <int>[],
    ]),
    maxBytes: 1,
    idleTimeout: const Duration(seconds: 1),
    totalTimeout: const Duration(seconds: 1),
  ).toList();
  if (chunks.length != 1 || chunks.single.join(',') != '1') {
    stderr.writeln('有界字节流未过滤空数据块');
    return 1;
  }
  return 0;
}

int _checkPortableFileNameSanitization() {
  if (isSafeStorageIdentifier('.') ||
      isSafeStorageIdentifier('..') ||
      isSafeStorageIdentifier('CON')) {
    stderr.writeln('isSafeStorageIdentifier 未拒绝保留目录或设备名');
    return 1;
  }
  if (sanitizePortableFileNamePart('.', fallback: 'session') != 'session' ||
      sanitizePortableFileNamePart('..', fallback: 'session') != 'session') {
    stderr.writeln('sanitizePortableFileNamePart 未阻止点目录标识符');
    return 1;
  }
  if (sanitizePortableFileNamePart(
        '  /unsafe///name/  ',
        collapseReplacement: true,
        trimBoundaryReplacement: true,
      ) !=
      'unsafe_name') {
    stderr.writeln('sanitizePortableFileNamePart 未正确收敛非法字符');
    return 1;
  }
  final bounded = sanitizePortableFileNamePart('a' * 300);
  if (bounded.length != kPortableFileNameDefaultMaxCharacters ||
      !isPortableFileNamePart(bounded)) {
    stderr.writeln('sanitizePortableFileNamePart 未限制跨平台文件名长度');
    return 1;
  }
  return 0;
}

int _checkPlatformShell() {
  if (posixShellQuote('') != "''" ||
      posixShellQuote("a'b") != "'a'\"'\"'b'" ||
      escapePowerShellSingleQuotedString("a'b") != "a''b" ||
      powerShellEncodedCommand("Write-Output '中'") !=
          'powershell.exe -NoProfile -NonInteractive -EncodedCommand '
              'VwByAGkAdABlAC0ATwB1AHQAcAB1AHQAIAAnAC1OJwA=') {
    stderr.writeln('平台 Shell 转义或 PowerShell 命令编码错误');
    return 1;
  }
  return 0;
}

int _checkPlatformEnvironment() {
  const environment = <String, String>{
    'Path': r'C:\Windows\System32',
    'localappdata': r'C:\Users\tester\AppData\Local',
  };
  if (platformEnvironmentValue(environment, 'PATH', caseInsensitive: true) !=
      environment['Path']) {
    stderr.writeln('platformEnvironmentValue 未兼容 Windows 环境变量大小写');
    return 1;
  }
  if (platformEnvironmentValue(environment, 'PATH', caseInsensitive: false) !=
      null) {
    stderr.writeln('platformEnvironmentValue 在大小写敏感模式下错误匹配了键名');
    return 1;
  }
  final merged = mergePlatformEnvironment(
    const <String, String>{'PATH': r'D:\Tools'},
    base: environment,
    caseInsensitive: true,
  );
  if (merged['PATH'] != r'D:\Tools' || merged.containsKey('Path')) {
    stderr.writeln('mergePlatformEnvironment 未按 Windows 语义覆盖同名变量');
    return 1;
  }
  return 0;
}

Future<int> _checkAbortableResponseLifetime() async {
  final client = _AbortableProbeClient();
  final request = http.Request('GET', Uri.parse('https://example.com/check'));
  final response = await sendAbortableHttpRequest(
    client: client,
    request: request,
    connectionTimeout: const Duration(seconds: 1),
  );
  final bytes = await response.stream.fold<List<int>>(
    <int>[],
    (all, chunk) => all..addAll(chunk),
  );
  await Future<void>.delayed(Duration.zero);
  final responseUrl = response is http.BaseResponseWithUrl
      ? (response as http.BaseResponseWithUrl).url
      : null;
  if (bytes.join(',') != '1,2,3' ||
      !client.requestLifetimeReleased ||
      responseUrl != request.url) {
    stderr.writeln('sendAbortableHttpRequest 未在响应流结束后释放取消监听。');
    return 1;
  }

  final pendingBody = StreamController<List<int>>();
  final cancelledClient = _AbortableProbeClient(bodyStream: pendingBody.stream);
  final cancelledResponse = await sendAbortableHttpRequest(
    client: cancelledClient,
    request: http.Request('GET', Uri.parse('https://example.com/cancel-check')),
    connectionTimeout: const Duration(seconds: 1),
  );
  final subscription = cancelledResponse.stream.listen(null);
  await Future<void>.delayed(Duration.zero);
  await subscription.cancel();
  await pendingBody.close();
  await Future<void>.delayed(Duration.zero);
  if (!cancelledClient.requestLifetimeReleased) {
    stderr.writeln('sendAbortableHttpRequest 未在响应流取消后释放取消监听。');
    return 1;
  }
  final immediateBodyCancelled = Completer<void>();
  final immediateBody = StreamController<List<int>>(
    onCancel: immediateBodyCancelled.complete,
  );
  final immediateClient = _AbortableProbeClient(
    bodyStream: immediateBody.stream,
  );
  final immediateResponse = await sendAbortableHttpRequest(
    client: immediateClient,
    request: http.Request('GET', Uri.parse('https://example.com/immediate')),
    connectionTimeout: const Duration(seconds: 1),
  );
  await immediateResponse.stream.listen(null).cancel();
  await Future<void>.delayed(Duration.zero);
  unawaited(immediateBody.close());
  if (!immediateClient.requestLifetimeReleased ||
      !immediateBodyCancelled.isCompleted) {
    stderr.writeln('响应体订阅后立即取消时未释放请求和底层流。');
    return 1;
  }
  final pausedBody = StreamController<List<int>>();
  final pausedClient = _AbortableProbeClient(bodyStream: pausedBody.stream);
  final pausedResponse = await sendAbortableHttpRequest(
    client: pausedClient,
    request: http.Request('GET', Uri.parse('https://example.com/paused')),
    connectionTimeout: const Duration(seconds: 1),
  );
  final received = <int>[];
  final readDone = Completer<void>();
  final pausedSubscription = pausedResponse.stream.listen(
    received.addAll,
    onDone: readDone.complete,
  )..pause();
  pausedBody.add(const [4, 5]);
  await Future<void>.delayed(Duration.zero);
  final pauseForwarded = pausedBody.isPaused && received.isEmpty;
  pausedSubscription.resume();
  await pausedBody.close();
  await readDone.future.timeout(const Duration(seconds: 1));
  await Future<void>.delayed(Duration.zero);
  if (!pauseForwarded ||
      received.join(',') != '4,5' ||
      !pausedClient.requestLifetimeReleased) {
    stderr.writeln('响应流未传递暂停、恢复或完成事件。');
    return 1;
  }
  final lateHeaders = Completer<void>();
  final bodyCancelled = Completer<void>();
  final lateBody = StreamController<List<int>>(
    onCancel: bodyCancelled.complete,
  );
  final lateClient = _AbortableProbeClient(
    bodyStream: lateBody.stream,
    beforeResponse: lateHeaders.future,
  );
  try {
    await sendAbortableHttpRequest(
      client: lateClient,
      request: http.Request('GET', Uri.parse('https://example.com/late')),
      connectionTimeout: const Duration(milliseconds: 10),
    );
    stderr.writeln('迟到响应未触发响应头超时。');
    return 1;
  } on TimeoutException {
    lateHeaders.complete();
    try {
      await bodyCancelled.future.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      stderr.writeln('响应头超时后未释放迟到响应体。');
      return 1;
    }
  } finally {
    if (!lateHeaders.isCompleted) lateHeaders.complete();
    unawaited(lateBody.close());
    lateClient.close();
  }
  return 0;
}

Future<int> _checkHttpCancellation() async {
  for (final cancelledBeforeSend in <bool>[true, false]) {
    final cancellation = Completer<void>();
    final headers = Completer<void>();
    final bodyCancelled = Completer<void>();
    final body = StreamController<List<int>>(onCancel: bodyCancelled.complete);
    final client = _AbortableProbeClient(
      bodyStream: body.stream,
      beforeResponse: headers.future,
    );
    if (cancelledBeforeSend) cancellation.complete();
    try {
      final pending = sendAbortableHttpRequest(
        client: client,
        request: http.Request('GET', Uri.parse('https://example.com/cancel')),
        connectionTimeout: const Duration(seconds: 5),
        cancelSignal: cancellation.future,
      );
      // 先监听错误，再在响应头未到达时取消。
      final result = pending.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      if (!cancelledBeforeSend) {
        await client.started.future;
        cancellation.complete();
      }
      final error = await result.timeout(const Duration(seconds: 1));
      if (error is! http.RequestAbortedException ||
          (cancelledBeforeSend && client.started.isCompleted)) {
        stderr.writeln('HTTP 取消未阻止发送或未保留取消错误。');
        return 1;
      }
      headers.complete();
      if (!cancelledBeforeSend) {
        await bodyCancelled.future.timeout(const Duration(seconds: 1));
      }
    } on TimeoutException {
      stderr.writeln('HTTP 取消仍等待响应头，或取消后未释放迟到响应体。');
      return 1;
    } finally {
      if (!headers.isCompleted) headers.complete();
      unawaited(body.close());
      client.close();
    }
  }
  return 0;
}

final class _AbortableProbeClient extends http.BaseClient {
  _AbortableProbeClient({this.bodyStream, this.beforeResponse});

  final Stream<List<int>>? bodyStream;
  final Future<void>? beforeResponse;
  bool requestLifetimeReleased = false;
  final started = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    started.complete();
    if (request is! http.AbortableRequest || request.abortTrigger == null) {
      throw StateError('请求未使用可取消传输。');
    }
    unawaited(
      request.abortTrigger!.then<void>((_) => requestLifetimeReleased = true),
    );
    await beforeResponse;
    return http.StreamedResponse(
      bodyStream ?? Stream<List<int>>.value(const <int>[1, 2, 3]),
      200,
      request: request,
    );
  }
}

int _checkSensitiveTextRedaction() {
  const token = '真实令牌ABC123';
  const password = '真实密码XYZ789';
  const privateKey =
      '-----BEGIN PRIVATE KEY-----\n私钥内容\n-----END PRIVATE KEY-----';
  final redacted = redactSensitiveText(
    'authorization: Bearer $token\n'
    'apiKey="$token"\n'
    'total_tokens=42\n'
    'https://user:$password@example.com/path?access_token=$token&view=full\n'
    '$privateKey\n'
    '-----BEGIN RSA PRIVATE KEY-----\n不完整私钥',
    replacement: '[已隐藏]',
  );
  if (redacted.contains(token) ||
      redacted.contains(password) ||
      redacted.contains('私钥内容') ||
      redacted.contains('不完整私钥') ||
      !redacted.contains('total_tokens=42') ||
      !redacted.contains('view=full') ||
      !redacted.contains('authorization: [已隐藏]')) {
    stderr.writeln('redactSensitiveText 未完整脱敏凭据或误删普通计数。');
    return 1;
  }
  return 0;
}

Future<int> _checkTemporaryByteStreamWrite() async {
  Directory? directory;
  try {
    directory = await createTemporaryDirectoryBounded(
      prefix: 'openhand-stream-write-check-',
      timeout: const Duration(seconds: 2),
    );
    final output = File('${directory.path}${Platform.pathSeparator}stream.bin');
    final progress = <int>[];
    final written = await writeTemporaryByteStreamBounded(
      output,
      Stream<List<int>>.fromIterable(const <List<int>>[
        <int>[1, 2],
        <int>[3, 4, 5],
      ]),
      maxBytes: 5,
      idleTimeout: const Duration(seconds: 1),
      totalTimeout: const Duration(seconds: 2),
      onProgress: progress.add,
    );
    if (written != 5 ||
        progress.isEmpty ||
        progress.last != 5 ||
        readBoundedFileBytesSync(output, maxBytes: 5).join(',') !=
            '1,2,3,4,5') {
      stderr.writeln('writeTemporaryByteStreamBounded 未完整写入有界字节流');
      return 1;
    }

    try {
      await writeTemporaryByteStreamBounded(
        output,
        Stream<List<int>>.value(const <int>[1, 2, 3]),
        maxBytes: 2,
        idleTimeout: const Duration(seconds: 1),
        totalTimeout: const Duration(seconds: 2),
      );
      stderr.writeln('writeTemporaryByteStreamBounded 应拒绝超长字节流');
      return 1;
    } on FileSystemException {
      if (output.existsSync()) {
        stderr.writeln('writeTemporaryByteStreamBounded 未清理失败半文件');
        return 1;
      }
    }
    return 0;
  } catch (error) {
    stderr.writeln('有界临时字节流写入检查失败：$error');
    return 1;
  } finally {
    await deleteTemporaryDirectoryBounded(directory);
  }
}

Future<int> _checkSynchronousBoundedFileRead() async {
  Directory? directory;
  try {
    directory = await createTemporaryDirectoryBounded(
      prefix: 'openhand-file-read-check-',
      timeout: const Duration(seconds: 2),
    );
    final file = File('${directory.path}${Platform.pathSeparator}marker.txt');
    file.writeAsStringSync('状态');
    if (readBoundedFileStringSync(file, maxBytes: 16) != '状态') {
      stderr.writeln('readBoundedFileStringSync 未读取出预期内容');
      return 1;
    }
    file.writeAsBytesSync(List<int>.filled(17, 0));
    try {
      readBoundedFileBytesSync(file, maxBytes: 16);
      stderr.writeln('readBoundedFileBytesSync 应拒绝超长文件');
      return 1;
    } on BoundedFileReadException {
      return 0;
    }
  } catch (error) {
    stderr.writeln('同步有界文件读取检查失败：$error');
    return 1;
  } finally {
    await deleteTemporaryDirectoryBounded(directory);
  }
}

Future<int> _checkTemporaryDirectoryLifecycle() async {
  Directory? directory;
  try {
    directory = await createTemporaryDirectoryBounded(
      prefix: 'openhand-shared-check-',
      timeout: const Duration(seconds: 2),
    );
    final invalidRoot = '${directory.parent.path}${Platform.pathSeparator}拒绝';
    final refused = await deleteTemporaryDirectoryBounded(
      directory,
      allowedRoot: invalidRoot,
    );
    if (refused || !await directory.exists()) {
      stderr.writeln('deleteTemporaryDirectoryBounded 未拒绝越界清理');
      return 1;
    }
    final deleted = await deleteTemporaryDirectoryBounded(directory);
    if (!deleted || await directory.exists()) {
      stderr.writeln('deleteTemporaryDirectoryBounded 未清理受管临时目录');
      return 1;
    }
    directory = null;
    return 0;
  } catch (error) {
    stderr.writeln('临时目录生命周期检查失败：$error');
    return 1;
  } finally {
    await deleteTemporaryDirectoryBounded(directory);
  }
}

int _checkJsonDecode() {
  var failures = 0;
  final validNull = tryDecodeJsonValue('null');
  if (!validNull.success || validNull.value != null) {
    stderr.writeln('tryDecodeJsonValue 未识别合法 JSON null');
    failures++;
  }
  if (tryDecodeJsonValue('{').success) {
    stderr.writeln('tryDecodeJsonValue 未拒绝无效 JSON');
    failures++;
  }
  if (tryDecodeJsonValue('[0]', maxTextCodeUnits: 2).success) {
    stderr.writeln('tryDecodeJsonValue 未拒绝超长 JSON');
    failures++;
  }
  final excessiveNesting = '${'[' * 65}0${']' * 65}';
  if (tryDecodeJsonValue(excessiveNesting).success) {
    stderr.writeln('tryDecodeJsonValue 未拒绝超深 JSON');
    failures++;
  }
  final decoded = decodeJsonTextUsingConfig(
    '{"a":1,"b":[true,null]}',
    maxTextCodeUnits: 64,
    config: kOpenHandProtocolJsonConversionConfig,
  );
  if (decoded is! Map || decoded['a'] != 1) {
    stderr.writeln('decodeJsonTextUsingConfig 未解析出对象字段 a=1');
    failures++;
  }
  final object = decodeJsonObjectTextUsingConfig(
    '{"name":"OpenHand"}',
    maxTextCodeUnits: 64,
  );
  if (object['name'] != 'OpenHand') {
    stderr.writeln('decodeJsonObjectTextUsingConfig 未解析出对象');
    failures++;
  }
  try {
    decodeJsonTextUsingConfig('{"a":1}', maxTextCodeUnits: 3);
    stderr.writeln('decodeJsonTextUsingConfig 应对超长文本抛出 FormatException');
    failures++;
  } on FormatException {
    // 符合预期。
  }
  try {
    decodeJsonTextUsingConfig(
      '{"a":"x"}',
      maxTextCodeUnits: 32,
      maxStringCodeUnits: 0,
    );
    stderr.writeln('decodeJsonTextUsingConfig 应严格执行零字符串预算');
    failures++;
  } on FormatException {
    // 符合预期。
  }
  try {
    decodeJsonTextUsingConfig(
      '[[[0]]]',
      maxTextCodeUnits: 32,
      config: const BoundedJsonConversionConfig(maxDepth: 2),
    );
    stderr.writeln('decodeJsonTextUsingConfig 应拒绝超深 JSON');
    failures++;
  } on FormatException {
    // 符合预期。
  }
  try {
    decodeJsonObjectTextUsingConfig('[1,2]', maxTextCodeUnits: 16);
    stderr.writeln('decodeJsonObjectTextUsingConfig 应拒绝非对象根节点');
    failures++;
  } on FormatException {
    // 符合预期。
  }
  return failures;
}

int _checkJsonEncodeFallback() {
  if (jsonEncodeOrString(<String, Object?>{'state': '就绪'}) !=
      '{"state":"就绪"}') {
    stderr.writeln('jsonEncodeOrString 未优先输出 JSON');
    return 1;
  }
  final cyclic = <Object?>[];
  cyclic.add(cyclic);
  if (jsonEncodeOrString(cyclic, fallback: '无法编码') != cyclic.toString()) {
    stderr.writeln('jsonEncodeOrString 未在 JSON 编码失败后回退文本');
    return 1;
  }
  return 0;
}

int _checkJsonMapKeyCollision() {
  final converted = convertToJsonSafeMap(<Object?, Object?>{
    1: '首项',
    '1': '冲突项',
  });
  if (converted['1'] != '首项' ||
      !converted.containsValue(
        const BoundedJsonConversionConfig().truncatedPlaceholder,
      )) {
    stderr.writeln('convertToJsonSafeMap 未显式处理字符串化键冲突');
    return 1;
  }
  return 0;
}

int _checkContentLength() {
  final parsed = parseHttpContentLengthHeader(
    'Content-Type: application/json\r\nContent-Length: 42\r\n',
    maxDigits: 8,
  );
  if (!parsed.found || parsed.value != 42) {
    stderr.writeln('parseHttpContentLengthHeader 未解析出 42，得到 $parsed');
    return 1;
  }
  final missing = parseHttpContentLengthHeader('Accept: */*\n', maxDigits: 8);
  if (missing.found || missing.value != null) {
    stderr.writeln('缺少 Content-Length 时应 found=false，得到 $missing');
    return 1;
  }
  final duplicate = parseHttpContentLengthHeader(
    'Content-Length: 1\nContent-Length: 2\n',
    maxDigits: 8,
  );
  if (!duplicate.found || duplicate.value != null) {
    stderr.writeln('重复 Content-Length 应判定无效，得到 $duplicate');
    return 1;
  }
  final invalid = parseHttpContentLengthHeader(
    'Content-Length: 12a\n',
    maxDigits: 8,
  );
  if (!invalid.found || invalid.value != null) {
    stderr.writeln('非数字 Content-Length 应判定无效，得到 $invalid');
    return 1;
  }
  return 0;
}

int _checkBackoff() {
  if (exponentialBackoffMs(attempt: 0, baseMs: 250, capMs: 4000) != 0) {
    stderr.writeln('attempt=0 的退避应为 0');
    return 1;
  }
  if (exponentialBackoffMs(attempt: 1, baseMs: 250, capMs: 4000) != 250) {
    stderr.writeln('第 1 次退避应为 250ms');
    return 1;
  }
  if (exponentialBackoffMs(attempt: 2, baseMs: 250, capMs: 4000) != 500) {
    stderr.writeln('第 2 次退避应为 500ms');
    return 1;
  }
  if (exponentialBackoffMs(attempt: 5, baseMs: 250, capMs: 4000) != 4000) {
    stderr.writeln('第 5 次退避应封顶 4000ms');
    return 1;
  }
  if (exponentialBackoffSeconds(attempt: 3, baseSeconds: 2, capSeconds: 10) !=
      8) {
    stderr.writeln('秒级退避 attempt=3 应为 8');
    return 1;
  }
  final durationBackoff = exponentialBackoffDuration(
    attempt: 5,
    base: const Duration(milliseconds: 250),
    cap: const Duration(seconds: 4),
  );
  if (durationBackoff.inMilliseconds !=
      exponentialBackoffMs(attempt: 5, baseMs: 250, capMs: 4000)) {
    stderr.writeln('Duration 退避应与毫秒公式一致，得到 $durationBackoff');
    return 1;
  }
  return 0;
}

int _checkDurationBounds() {
  if (nonNegativeDuration(const Duration(milliseconds: -40)) != Duration.zero) {
    stderr.writeln('nonNegativeDuration 未把负时长归零');
    return 1;
  }
  if (shorterDuration(
        const Duration(milliseconds: 80),
        const Duration(milliseconds: 20),
      ) !=
      const Duration(milliseconds: 20)) {
    stderr.writeln('shorterDuration 未取较短者');
    return 1;
  }
  if (clampDuration(
        const Duration(milliseconds: -8),
        min: Duration.zero,
        max: const Duration(milliseconds: 120),
      ) !=
      Duration.zero) {
    stderr.writeln('clampDuration 未夹到下限');
    return 1;
  }
  if (clampDuration(
        const Duration(milliseconds: 500),
        min: const Duration(milliseconds: 80),
        max: const Duration(milliseconds: 120),
      ) !=
      const Duration(milliseconds: 120)) {
    stderr.writeln('clampDuration 未夹到上限');
    return 1;
  }
  if (clampDuration(
        const Duration(milliseconds: 90),
        min: const Duration(milliseconds: 200),
        max: const Duration(milliseconds: 40),
      ) !=
      const Duration(milliseconds: 90)) {
    stderr.writeln('clampDuration 未在颠倒边界内保留合法值');
    return 1;
  }
  return 0;
}

int _checkIntegerValueRange() {
  const range = IntValueRange(fallback: 360, min: 80, max: 1200);
  if (range.normalize(40) != 80 ||
      range.normalize(5000) != 1200 ||
      range.normalize(360) != 360) {
    stderr.writeln('整数范围归一化未正确夹取边界或保留合法值');
    return 1;
  }
  return 0;
}

int _checkPrettyJsonIfDecodable() {
  if (prettyPrintJson(<String, Object?>{'state': '就绪'}) !=
      '{\n  "state": "就绪"\n}') {
    stderr.writeln('prettyPrintJson 未按双空格缩进输出');
    return 1;
  }
  if (prettyPrintJsonIfDecodable('{"a":1}') != '{\n  "a": 1\n}') {
    stderr.writeln('prettyPrintJsonIfDecodable 未格式化合法 JSON');
    return 1;
  }
  if (prettyPrintJsonIfDecodable('  not-json  ') != 'not-json') {
    stderr.writeln('prettyPrintJsonIfDecodable 未原样返回非法 JSON');
    return 1;
  }
  return 0;
}

int _checkLoopback() {
  if (!isLoopbackHost('127.0.0.1') ||
      !isLoopbackHost('localhost') ||
      !isLoopbackHost('LOCALHOST.localdomain') ||
      !isLoopbackHost('[::1]') ||
      !isLoopbackHost('::ffff:127.0.0.1')) {
    stderr.writeln('isLoopbackHost 未识别回环地址');
    return 1;
  }
  if (isLoopbackHost('example.com') || isLoopbackHost('8.8.8.8')) {
    stderr.writeln('isLoopbackHost 误判了非回环地址');
    return 1;
  }
  if (!kLoopbackHosts.contains('127.0.0.1')) {
    stderr.writeln('kLoopbackHosts 缺少 127.0.0.1');
    return 1;
  }
  if (!isLoopbackHostname('LOCALHOST.localdomain') ||
      !isLoopbackHostname('api.localhost') ||
      isLoopbackHostname('127.0.0.1') ||
      isLoopbackHostname('example.com')) {
    stderr.writeln('isLoopbackHostname 主机名判定错误');
    return 1;
  }
  return 0;
}

int _checkStringFromValue() {
  if (stringFromValue(null, fallback: 'x') != 'x') {
    stderr.writeln('stringFromValue(null) 未回落');
    return 1;
  }
  if (stringFromValue('  hi ') != 'hi') {
    stderr.writeln('stringFromValue 未 trim');
    return 1;
  }
  final map = stringKeyedMapFromValue(<Object?, Object?>{1: 'a'});
  if (map['1'] != 'a') {
    stderr.writeln('stringKeyedMapFromValue 未把键转为字符串');
    return 1;
  }
  return 0;
}

int _checkFiniteNumberParsing() {
  if (optionalNumFromValue('42') != 42 ||
      optionalNumFromValue('3.5') != 3.5 ||
      optionalDoubleFromValue(7) != 7.0) {
    stderr.writeln('有限数值解析结果错误');
    return 1;
  }
  if (optionalNumFromValue('NaN') != null ||
      optionalNumFromValue('Infinity') != null ||
      optionalDoubleFromValue(double.negativeInfinity) != null) {
    stderr.writeln('有限数值解析未拒绝非有限值');
    return 1;
  }
  return 0;
}

int _checkGrowableStringKeyedMap() {
  final global = growableStringKeyedMapFromValue(null);
  global['body'] = <String, Object?>{'n': 1};
  global['headers'] = <String, String>{'x': 'y'};
  final body = optionalStringKeyedMapFromValue(global['body']);
  if (body == null || body['n'] != 1) {
    stderr.writeln('growableStringKeyedMapFromValue(null) 写入 body 失败');
    return 1;
  }
  final headers = global['headers'];
  if (headers is! Map || headers['x'] != 'y') {
    stderr.writeln('growableStringKeyedMapFromValue(null) 写入 headers 失败');
    return 1;
  }

  const writtenTemperature = 0.4;
  final source = <String, Object?>{'topK': 8};
  final generationConfig = growableStringKeyedMapFromValue(source);
  generationConfig['temperature'] = writtenTemperature;
  if (identical(generationConfig, source) ||
      source.containsKey('temperature')) {
    stderr.writeln('growableStringKeyedMapFromValue 别名或回写了源映射');
    return 1;
  }
  if (generationConfig['topK'] != source['topK'] ||
      generationConfig['temperature'] != writtenTemperature) {
    stderr.writeln('growableStringKeyedMapFromValue 未保留源字段或写入失败');
    return 1;
  }
  return 0;
}

int _checkHttpRetryableStatus() {
  if (!isHttpTransientRetryableStatus(kHttpRequestTimeoutStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpTooEarlyStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpTooManyRequestsStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpInternalServerErrorStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpBadGatewayStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpServiceUnavailableStatusCode) ||
      !isHttpTransientRetryableStatus(kHttpGatewayTimeoutStatusCode)) {
    stderr.writeln('isHttpTransientRetryableStatus 未识别瞬时失败状态码');
    return 1;
  }
  if (isHttpTransientRetryableStatus(kHttpConflictStatusCode) ||
      isHttpTransientRetryableStatus(404) ||
      isHttpTransientRetryableStatus(kHttpSuccessStatusMin)) {
    stderr.writeln('isHttpTransientRetryableStatus 误判了非瞬时状态码');
    return 1;
  }
  if (!isHttpServerErrorStatus(501) || isHttpServerErrorStatus(499)) {
    stderr.writeln('isHttpServerErrorStatus 判定错误');
    return 1;
  }
  return 0;
}

int _checkRgbHex() {
  if (rgbHexFromArgb32(0xFF1E1E24) != '1e1e24') {
    stderr.writeln('rgbHexFromArgb32(0xFF1E1E24) 应为 1e1e24');
    return 1;
  }
  if (rgbHexFromArgb32(0x000000FF) != '0000ff') {
    stderr.writeln('rgbHexFromArgb32 未补齐 6 位');
    return 1;
  }
  return 0;
}

int _checkXmlEscape() {
  final escaped = escapeXmlAttribute('''a&b<"c">'d''');
  if (!escaped.contains('&amp;') ||
      !escaped.contains('&lt;') ||
      !escaped.contains('&quot;') ||
      !escaped.contains('&gt;') ||
      !escaped.contains('&apos;')) {
    stderr.writeln('escapeXmlAttribute 未转义全部 XML 属性字符，得到 $escaped');
    return 1;
  }
  if (escapeXmlAttribute('plain') != 'plain') {
    stderr.writeln('escapeXmlAttribute 不应改写无特殊字符的文本');
    return 1;
  }
  return 0;
}

int _checkCompactDuration() {
  if (formatCompactDuration(const Duration(seconds: 5)) != '5s') {
    stderr.writeln('formatCompactDuration(5s) 应为 5s');
    return 1;
  }
  if (formatCompactDuration(const Duration(seconds: 65)) != '1m 5s') {
    stderr.writeln('formatCompactDuration(65s) 应为 1m 5s');
    return 1;
  }
  if (formatCompactDurationMs(250) !=
      formatCompactDuration(const Duration(milliseconds: 250))) {
    stderr.writeln('formatCompactDurationMs 应与 Duration 形式一致');
    return 1;
  }
  return 0;
}

int _checkCalendarDateMath() {
  final leapFebruary = shiftCalendarMonths(DateTime(2024, 3, 31), -1);
  if (leapFebruary != DateTime(2024, 2, 29)) {
    stderr.writeln('shiftCalendarMonths 未正确夹到闰年二月末');
    return 1;
  }
  final minimum = shiftCalendarMonths(DateTime(1, 1, 31), -1000);
  if (minimum != DateTime(1, 1, 31)) {
    stderr.writeln('shiftCalendarMonths 未正确限制最小日历月份');
    return 1;
  }
  final maximum = shiftCalendarMonths(DateTime(9999, 12, 31), 1000);
  if (maximum != DateTime(9999, 12, 31)) {
    stderr.writeln('shiftCalendarMonths 未正确限制最大日历月份');
    return 1;
  }
  final window = rollingCalendarDateWindow(
    DateTime(2026, 3, 10, 18),
    daysInclusive: 3,
  );
  if (window.start != DateTime(2026, 3, 8) ||
      window.end != DateTime(2026, 3, 10)) {
    stderr.writeln('rollingCalendarDateWindow 未按本地日历日生成窗口');
    return 1;
  }
  return 0;
}

int _checkCanonicalDateTime() {
  const utcText = '2026-09-08T12:34:56.000Z';
  final utc = canonicalDateTimeFromValue(utcText, requireUtc: true);
  if (utc == null || !utc.isUtc || utc.toIso8601String() != utcText) {
    stderr.writeln('canonicalDateTimeFromValue 未接受规范 UTC 时间');
    return 1;
  }
  if (canonicalDateTimeFromValue(
        '2026-09-08T20:34:56.000+08:00',
        requireUtc: true,
      ) !=
      null) {
    stderr.writeln('canonicalDateTimeFromValue 应拒绝非规范 UTC 文本');
    return 1;
  }
  const localText = '2026-09-08T12:34:56.000';
  if (canonicalDateTimeFromValue(localText)?.toIso8601String() != localText ||
      canonicalDateTimeFromValue(localText, requireUtc: true) != null) {
    stderr.writeln('canonicalDateTimeFromValue 本地时间边界处理错误');
    return 1;
  }
  return 0;
}

int _checkTextClip() {
  final clipped = clipText('12345678', 7);
  if (clipped != '1234...' || clipped.length > 7) {
    stderr.writeln('clipText 返回值超过字符上限');
    return 1;
  }
  if (clipText('内容', 2) != '内容' || clipText('内容', 0).isNotEmpty) {
    stderr.writeln('clipText 未正确处理边界长度');
    return 1;
  }
  if (clipText('👨‍👩‍👧‍👦尾', 1, suffix: '') != '👨‍👩‍👧‍👦') {
    stderr.writeln('clipText 拆分了扩展字符');
    return 1;
  }
  final longText = '👨‍👩‍👧‍👦${'正文' * 100000}🇨🇳';
  if (clipText(longText, 3) != '...' ||
      clipText(longText, 3, suffix: '') != '👨‍👩‍👧‍👦正文' ||
      clipMiddleText(longText, maxChars: 3, headFraction: 0.5) !=
          '👨‍👩‍👧‍👦…🇨🇳' ||
      clipMiddleText('👨‍👩‍👧‍👦🇨🇳', maxChars: 2) != '👨‍👩‍👧‍👦🇨🇳' ||
      clipText(longText, 1, suffix: '🇨🇳🇺🇸') != '🇨🇳') {
    stderr.writeln('长正文预览或首尾扩展字符裁剪错误');
    return 1;
  }
  return 0;
}

int _checkTextSearch() {
  final offsets = findTextMatchOffsets(
    text: 'Alpha alpha',
    query: 'alpha',
    allowOverlapping: false,
  );
  if (offsets.join(',') != '0,6' ||
      moveTextMatchIndex(currentIndex: -1, matchCount: 2, forward: true) != 0 ||
      moveTextMatchIndex(currentIndex: -1, matchCount: 2, forward: false) !=
          1 ||
      moveTextMatchIndex(currentIndex: 1, matchCount: 2, forward: true) != 0 ||
      moveTextMatchIndex(currentIndex: 0, matchCount: 2, forward: false) != 1 ||
      moveTextMatchIndex(currentIndex: 0, matchCount: 0, forward: true) != -1) {
    stderr.writeln('文本查找偏移或循环导航边界错误');
    return 1;
  }
  return 0;
}

int _checkBoundedTextBuffer() {
  final buffer = BoundedTextBuffer(maxCharacters: 5);
  buffer
    ..append('12')
    ..append('34')
    ..append('56');
  if (buffer.text != '23456' ||
      buffer.startOffset != 1 ||
      buffer.endOffset != 6 ||
      buffer.textFrom(4) != '56') {
    stderr.writeln('BoundedTextBuffer 未正确保留最新文本或绝对偏移');
    return 1;
  }

  buffer
    ..clear()
    ..append('1234')
    ..append('😀');
  if (buffer.text != '234😀' || buffer.length != 5) {
    stderr.writeln('BoundedTextBuffer 裁剪时破坏了 UTF-16 代理对');
    return 1;
  }
  return 0;
}

int _checkLifecycleCache() {
  const largeCost = 1 << 62;
  final cache = LifecycleLruCache<int>(
    maxEntries: 3,
    maxCost: largeCost + 1,
    costOf: (value) => value,
  );
  cache
    ..put('旧条目', largeCost)
    ..put('新条目', largeCost);
  if (cache.containsKey('旧条目') || !cache.containsKey('新条目')) {
    stderr.writeln('缓存成本相加溢出后未遵守预算');
    return 1;
  }
  cache.put('待回填', 1);
  if (!cache.updateCostIfIdentical('待回填', 1, largeCost) ||
      cache.containsKey('新条目')) {
    stderr.writeln('缓存回填成本溢出或未淘汰旧条目');
    return 1;
  }
  cache
    ..clear()
    ..put('旧条目', 1)
    ..put('新条目', largeCost);
  if (cache.updateCostIfIdentical('旧条目', 1, largeCost) ||
      !cache.containsKey('新条目')) {
    stderr.writeln('回填被淘汰的旧条目时错误删除了新条目');
    return 1;
  }
  final nullable = LifecycleLruCache<String?>(maxEntries: 2);
  nullable.put('空值', null);
  var created = false;
  nullable.putIfAbsent('空值', () {
    created = true;
    return '不应创建';
  });
  if (created || !nullable.removeIfIdentical('空值', null)) {
    stderr.writeln('缓存未正确区分空值与缺失条目');
    return 1;
  }
  return 0;
}

Future<int> _checkBatchSubscriptionCancellation() async {
  var firstCancelled = false;
  var secondCancelled = false;
  final firstController = StreamController<void>(
    onCancel: () => firstCancelled = true,
  );
  final secondController = StreamController<void>(
    onCancel: () => secondCancelled = true,
  );
  final first = firstController.stream.listen(null);
  final second = secondController.stream.listen(null);
  final succeeded = await cancelStreamSubscriptionsBounded(
    <StreamSubscription<dynamic>>[first, second, first],
  );
  await Future.wait<void>(<Future<void>>[
    firstController.close(),
    secondController.close(),
  ]);
  if (!succeeded || !firstCancelled || !secondCancelled) {
    stderr.writeln('cancelStreamSubscriptionsBounded 未完整取消订阅');
    return 1;
  }
  return 0;
}

int _checkTranscriptHistory() {
  for (final count in [0, 4, 8, 13, 100, 1000]) {
    var start = TranscriptListWindowing.initialWindowStartIndex(count);
    for (var page = 0; page <= count ~/ 6 + 1; page++) {
      final range = TranscriptListWindowing.visibleRange(
        preferredStart: start,
        messageCount: count,
      );
      if (range.end != count || range.start != start) {
        stderr.writeln('展开历史后丢失最新尾部：总数 $count，起点 $start');
        return 1;
      }
      final appendedStart = TranscriptListWindowing.windowStartAfterAppend(
        previousWindowStart: start,
        messageCount: count + 10,
      );
      if (appendedStart != start) {
        stderr.writeln('追加消息不能收回已展开的历史');
        return 1;
      }
      if (start == 0) break;
      start = TranscriptListWindowing.revealOlderWindowStart(start);
    }
  }
  final start = TranscriptListWindowing.windowStartAfterHistoryPrepend(
    previousWindowStart: 0,
    addedDisplayCount: 40,
  );
  final hydrated = TranscriptListWindowing.visibleRange(
    preferredStart: start,
    messageCount: 140,
  );
  if (hydrated.end != 140 || hydrated.start >= 40) {
    stderr.writeln('存储分页必须展开更早内容并保留全部旧窗口');
    return 1;
  }
  return 0;
}

Future<int> _checkLateNativeHttpResponse() async {
  final request = _LateHttpRequest();
  try {
    await closeHttpClientRequestBounded(
      request,
      timeout: const Duration(milliseconds: 10),
    );
    stderr.writeln('响应头等待未按时结束');
    return 1;
  } on TimeoutException {
    if (!request.aborted) {
      stderr.writeln('响应头超时没有中止请求');
      return 1;
    }
  }
  final released = Completer<void>();
  final body = StreamController<List<int>>(onCancel: released.complete);
  request.response.complete(_LateHttpResponse(body.stream));
  try {
    await released.future.timeout(const Duration(seconds: 1));
  } on TimeoutException {
    stderr.writeln('响应头超时后没有释放迟到的响应体');
    return 1;
  } finally {
    unawaited(body.close());
  }
  return 0;
}

final class _LateHttpRequest implements HttpClientRequest {
  final response = Completer<HttpClientResponse>();
  bool aborted = false;

  @override
  Future<HttpClientResponse> close() => response.future;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) => aborted = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LateHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _LateHttpResponse(this.body);
  final Stream<List<int>> body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int _checkSkillMarketMapping() {
  final detail = SkillHubSkillMapper.skillMarketDetail({
    'skill': {
      'slug': '检查技能',
      'tags': {'latest': '1.2.3'},
    },
    'owner': {'displayName': '发布者'},
    'latestVersion': {'version': '1.2.3', 'changelog': '更新内容'},
    'securityReports': {
      '扫描': {'status': 'passed', 'statusText': '通过'},
    },
  });
  final files = SkillHubSkillMapper.skillMarketFiles({
    'files': [
      {'path': 'SKILL.md', 'size': 42},
    ],
  });
  final versions = SkillHubSkillMapper.skillMarketVersions({
    'versions': [
      {'version': '1.2.3', 'changelog': '更新内容'},
    ],
  });
  if (detail.skill.latestTag != '1.2.3' ||
      detail.owner.displayName != '发布者' ||
      detail.securityReports['扫描']?.status != 'passed' ||
      detail.latestVersion?.version != '1.2.3' ||
      files.single.path != 'SKILL.md' ||
      files.single.size != 42 ||
      versions.single.changelog != '更新内容' ||
      SkillHubSkillMapper.skillMarketFiles({}).isNotEmpty ||
      SkillHubSkillMapper.skillMarketVersions({}).isNotEmpty) {
    stderr.writeln('技能市场精简模型后丢失展示、安装或安全报告数据。');
    return 1;
  }
  return 0;
}
