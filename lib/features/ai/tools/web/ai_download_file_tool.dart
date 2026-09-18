import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/url_validation.dart';
import '../../../../shared/net/abortable_http_request.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_response_utils.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/path_safety.dart';
import '../../../../shared/util/storage_identifier.dart';
import '../../../../shared/util/timer_safety.dart';
import '../../model/ai_attachment.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';
import '../web_reverse_cdp_first_guard.dart';

/// 下载原始文件到会话附件目录；成功后才发布附件，不压缩或解码文件正文。
class AiDownloadFileTool extends AiTool {
  AiDownloadFileTool({
    required this.httpClient,
    Future<List<InternetAddress>> Function(String host)? hostLookup,
    String Function(String sessionId)? directoryProvider,
    this.timeout = const Duration(seconds: 90),
  }) : hostLookup = hostLookup ?? InternetAddress.lookup,
       directoryProvider =
           directoryProvider ??
           ((sessionId) => p.join(
             OpenHandPaths.defaultSessionsDirectoryPath(),
             sessionId,
             'attachments',
           ));

  final http.Client httpClient;
  final Future<List<InternetAddress>> Function(String host) hostLookup;
  final String Function(String sessionId) directoryProvider;
  final Duration timeout;
  static const int maxBytes = 512 * 1024 * 1024;
  static const int maxRedirects = 5;
  static const Duration idleTimeout = Duration(seconds: 30);
  static const Map<String, String> _mimeExtensions = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'image/svg+xml': '.svg',
    'image/bmp': '.bmp',
    'video/mp4': '.mp4',
    'video/webm': '.webm',
    'audio/mpeg': '.mp3',
    'audio/mp4': '.m4a',
    'audio/wav': '.wav',
    'audio/ogg': '.ogg',
    'application/pdf': '.pdf',
    'application/zip': '.zip',
  };

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.downloadFile;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final uri = tryParseValidHttpUrl(
      AiToolUtils.readString(context.decodedArguments['url']),
    );
    if (uri == null) {
      return AiToolUtils.invalidResult(
        'DownloadFile',
        '需要有效的 HTTP 或 HTTPS 文件直链。',
      );
    }
    final config =
        (context.catalog.find(context.toolCall.name) ??
                context.catalog.findDeferredTool(context.toolCall.name))
            ?.builtinConfig;
    final duration = config == null
        ? timeout
        : Duration(seconds: config.effectiveTimeoutSeconds);
    final deadline = MonotonicDeadline(duration, timeoutMessage: '文件下载超过总时限。');
    final abort = Completer<void>();
    var timedOut = false;
    final timer = startSafeTimer(duration, () {
      timedOut = true;
      if (!abort.isCompleted) abort.complete();
    });
    final cancelSignal = combineCancelSignals([
      context.cancelSignal,
      abort.future,
    ]);
    final watch = Stopwatch()..start();
    File? file;
    http.StreamedResponse? response;
    var consumed = false;
    var succeeded = false;
    final command = 'DownloadFile ${uri.origin}${uri.path}';
    void checkCancellation() {
      if (timedOut) throw TimeoutException('文件下载超过总时限。');
    }

    try {
      if (await isCancelSignalCompleted(context.cancelSignal)) {
        throw const _DownloadCancelled();
      }
      final sessionId = requireSafeStorageIdentifier(
        context.sessionId,
        label: '会话标识符',
      );
      response = await sendHttpRequestFollowingRedirects(
        client: httpClient,
        method: 'GET',
        uri: uri,
        headers: const {'accept': '*/*'},
        timeout: deadline.limit(idleTimeout),
        maxRedirects: maxRedirects,
        cancelSignal: cancelSignal,
        beforeRequest: (target) async {
          checkCancellation();
          if (await isCancelSignalCompleted(context.cancelSignal)) {
            throw const _DownloadCancelled();
          }
          final block = WebReverseCdpFirstGuard.evaluateUrl(
            requestedUri: target,
            metadata: context.metadata,
          );
          if (block != null) {
            throw StateError('该地址须先通过浏览器工具访问：${block.targetOrigin}。');
          }
          final reason = await awaitWithCancelSignal(
            agentFetchBlockReasonForResolvedUri(
              target,
              hostLookup: hostLookup,
            ).timeout(deadline.limit(idleTimeout)),
            cancelSignal: cancelSignal,
          );
          checkCancellation();
          if (await isCancelSignalCompleted(context.cancelSignal)) {
            throw const _DownloadCancelled();
          }
          if (reason != null) throw StateError('不能下载该地址：$reason。');
        },
        drainResponse: (item) async {
          await cancelByteStream(item.stream);
        },
        onTooManyRedirects: (item) async {
          await cancelByteStream(item.stream);
          throw StateError('下载重定向超过 $maxRedirects 次。');
        },
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('下载失败，HTTP 状态码 ${response.statusCode}。');
      }
      if ((response.contentLength ?? 0) > maxBytes) {
        throw StateError('文件超过 512 MB 上限。');
      }
      final mime = responseMimeType(response.headers);
      if (mime == 'text/html' || mime == 'application/xhtml+xml') {
        throw StateError('链接返回网页，请查找原始文件直链后重试。');
      }
      final finalUri = response is http.BaseResponseWithUrl
          ? (response as http.BaseResponseWithUrl).url
          : uri;
      final name = _fileName(
        context.decodedArguments['filename'],
        response.headers,
        finalUri,
        mime,
      );
      final directory = Directory(directoryProvider(sessionId));
      await directory
          .create(recursive: true)
          .timeout(deadline.limit(idleTimeout));
      final id = const Uuid().v4();
      file = File(p.join(directory.path, '$id-$name'));
      var lastProgressMs = -500;
      void reportProgress(int bytes) {
        final elapsed = watch.elapsedMilliseconds;
        if (elapsed - lastProgressMs < 500) return;
        lastProgressMs = elapsed;
        context.onBashUpdate?.call(
          BashToolExecutionUpdate(
            phase: BashToolExecutionPhase.running,
            command: command,
            workingDirectory: directory.path,
            stdout: '正在下载 $name：已接收 $bytes 字节',
            stderr: '',
            durationMs: elapsed,
          ),
        );
      }

      reportProgress(0);
      consumed = true;
      final bytes = await writeTemporaryByteStreamBounded(
        file,
        response.stream.map((chunk) {
          checkCancellation();
          return chunk;
        }),
        maxBytes: maxBytes,
        idleTimeout: deadline.limit(idleTimeout),
        totalTimeout: deadline.remaining(),
        onProgress: reportProgress,
        onSecondaryError: (error, stack) =>
            silentLog('download_file', '清理下载资源', error, stack),
      );
      checkCancellation();
      if (await isCancelSignalCompleted(context.cancelSignal)) {
        throw const _DownloadCancelled();
      }
      if (bytes == 0) throw StateError('下载文件为空。');
      final expectedBytes = response.contentLength;
      if (expectedBytes != null &&
          readResponseHeader(response.headers, 'content-encoding').isEmpty &&
          expectedBytes != bytes) {
        throw StateError('下载文件不完整，请重试。');
      }
      final attachment = AiMessageAttachment(
        id: id,
        name: name,
        storagePath: p.absolute(file.path),
        kind: aiAttachmentKindForPath(name),
        mimeType: mime.isEmpty ? aiMimeTypeForPath(name) : mime,
        sizeBytes: bytes,
      );
      final deliver = context.decodedArguments['attach_to_reply'] != false;
      final output = jsonEncode({
        '文件': attachment.toJson(),
        '附加到最终回复': deliver,
      });
      succeeded = true;
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.success,
        command: command,
        workingDirectory: directory.path,
        stdout: output,
        stderr: '',
        durationMs: watch.elapsedMilliseconds,
        resultText: output,
        metadata: {
          if (deliver)
            aiSessionDownloadedFilesMetadataKey:
                AiMessageAttachment.listToMetadata([attachment]),
        },
      );
    } catch (error) {
      final cancelled =
          error is _DownloadCancelled ||
          !timedOut &&
              (isHttpRequestAborted(error) ||
                  await isCancelSignalCompleted(context.cancelSignal));
      final status = timedOut || error is TimeoutException
          ? BashToolExecutionStatus.timedOut
          : cancelled
          ? BashToolExecutionStatus.cancelled
          : BashToolExecutionStatus.failed;
      final message = cancelled
          ? '文件下载已取消。'
          : timedOut
          ? '文件下载超过总时限。'
          : '文件下载失败：$error';
      return AiToolExecutionResult(
        status: status,
        command: command,
        workingDirectory: '',
        stdout: '',
        stderr: message,
        durationMs: watch.elapsedMilliseconds,
        resultText: message,
      );
    } finally {
      timer.cancel();
      deadline.stop();
      if (!abort.isCompleted) abort.complete();
      if (response != null && !consumed) {
        await cancelByteStream(response.stream);
      }
      if (!succeeded && file != null) {
        await runAsyncCleanupBounded(
          () async {
            if (await file!.exists()) await file!.delete();
          },
          onError: (error, stack) =>
              silentLog('download_file', '删除未完成下载', error, stack),
        );
      }
    }
  }

  String _fileName(
    Object? requested,
    Map<String, String> headers,
    Uri uri,
    String mime,
  ) {
    var name = AiToolUtils.readString(requested);
    if (name.isEmpty) {
      final disposition = readResponseHeader(headers, 'content-disposition');
      final extended = RegExp(
        r"filename\*\s*=\s*UTF-8''([^;]+)",
        caseSensitive: false,
      ).firstMatch(disposition);
      final ordinary = RegExp(
        r'''filename\s*=\s*"?([^";]+)''',
        caseSensitive: false,
      ).firstMatch(disposition);
      name =
          extended?.group(1) ??
          ordinary?.group(1) ??
          (uri.pathSegments.isEmpty ? '' : uri.pathSegments.last);
      if (extended != null) {
        try {
          name = Uri.decodeComponent(name);
        } on FormatException {
          name = '';
        }
      }
    }
    name = sanitizePortableFileNamePart(
      name,
      fallback: '下载文件',
      allowWhitespace: true,
      maxUtf8Bytes: 180,
    );
    final extension = _mimeExtensions[mime];
    if (extension != null && aiMimeTypeForPath(name) != mime) {
      name = '${p.withoutExtension(name)}$extension';
    }
    return name;
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
