import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app/support/silent_log.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/timer_safety.dart';

/// Web 逆向会话的产物落盘：把 dashboard 实时缓冲的网络/控制台事件
/// 流式追加到 `~/.openhand/web_reverse/<session_id>/{network,console}.jsonl`，
/// 同时维护一份 HAR 1.2 的草稿，会话结束时一次性写出。
///
/// 设计要点：
/// - 600ms throttle flush：高频事件下不会每条都触发 IO 系统调用。
/// - jsonl 一行一条事件，方便模型用 `tail -N` / `grep` 直接读。
/// - HAR 写在会话 stop() 时落盘，避免运行期 IO 抢带宽。
/// - 任何 IO 失败均吞掉到 silentLog；artifact 不应阻塞 controller。
class WebReverseSessionArtifacts {
  WebReverseSessionArtifacts({
    required this.rootDir,
    Duration flushInterval = const Duration(milliseconds: 600),
  }) : _flushInterval = flushInterval;

  /// 会话工作目录，例如 `~/.openhand/web_reverse/<session_id>`。
  final String rootDir;
  final Duration _flushInterval;

  IOSink? _networkSink;
  IOSink? _consoleSink;
  bool _ready = false;
  bool _closed = false;
  Timer? _flushTimer;
  Future<void>? _initFuture;
  Future<void>? _closeFuture;

  // 写缓冲：保存待 flush 的字符串行；flush 时合并写入。
  final StringBuffer _networkBuf = StringBuffer();
  final StringBuffer _consoleBuf = StringBuffer();
  final Set<String> _reportedBufferDrops = <String>{};

  // HAR 草稿：每条 request/response 元数据按 requestId 累积，stop 时聚合。
  final Map<String, _HarEntryDraft> _harDrafts = <String, _HarEntryDraft>{};

  static const int _maxHarDrafts = 2000;
  static const int _maxHarHeaders = 128;
  static const int _maxHarHeaderValueChars = 8192;
  static const int _maxHarPostDataChars = 256 * 1024;
  static const int _maxJsonlEventChars = 1 * kBytesPerMiB;
  static const int _maxJsonlPendingChars = 4 * kBytesPerMiB;

  Future<void> init() {
    if (_closed || _ready) return Future<void>.value();
    final existing = _initFuture;
    if (existing != null) return existing;
    late final Future<void> initializing;
    initializing = _initialize().whenComplete(() {
      if (identical(_initFuture, initializing)) _initFuture = null;
    });
    _initFuture = initializing;
    return initializing;
  }

  Future<void> _initialize() async {
    IOSink? networkSink;
    IOSink? consoleSink;
    try {
      await Directory(rootDir).create(recursive: true);
      await Directory('$rootDir/network').create(recursive: true);
      await Directory('$rootDir/scripts').create(recursive: true);
      await Directory('$rootDir/screenshots').create(recursive: true);
      await Directory('$rootDir/har').create(recursive: true);
      if (_closed) return;
      networkSink = File(
        '$rootDir/network.jsonl',
      ).openWrite(mode: FileMode.append);
      consoleSink = File(
        '$rootDir/console.jsonl',
      ).openWrite(mode: FileMode.append);
      if (_closed) {
        await Future.wait<bool>(<Future<bool>>[
          _closeSink(networkSink, 'late network'),
          _closeSink(consoleSink, 'late console'),
        ]);
        return;
      }
      _networkSink = networkSink;
      _consoleSink = consoleSink;
      _ready = true;
      _flushTimer = startSafePeriodicTimer(_flushInterval, (_) => _flush());
      networkSink = null;
      consoleSink = null;
    } catch (error, stack) {
      _flushTimer?.cancel();
      _flushTimer = null;
      _networkSink = null;
      _consoleSink = null;
      _ready = false;
      silentLog('web_reverse_artifacts', 'init', error, stack);
      await Future.wait<bool>(<Future<bool>>[
        _closeSink(networkSink, 'failed network'),
        _closeSink(consoleSink, 'failed console'),
      ]);
    }
  }

  /// 追加一条网络事件行。`event` 自由 schema，但以下字段约定俗成：
  ///   - `kind`: 'request' | 'response' | 'failed'
  ///   - `request_id`, `url`, `method`, `status`, `mime`, `error`, `ts`
  void appendNetwork(Map<String, Object?> event) {
    _appendJsonLine(_networkBuf, event, 'network');
  }

  void appendConsole(Map<String, Object?> event) {
    _appendJsonLine(_consoleBuf, event, 'console');
  }

  /// 累积 HAR 草稿：CDP `Network.requestWillBeSent` / `responseReceived` /
  /// `loadingFinished` / `loadingFailed` 都喂进来，stop() 时再合成 HAR。
  void recordHarRequest({
    required String requestId,
    required String url,
    required String method,
    required Map<String, Object?> headers,
    String? postData,
    required DateTime startedAt,
  }) {
    if (_closed) return;
    final draft = _harDrafts.putIfAbsent(
      requestId,
      () => _HarEntryDraft(requestId: requestId),
    );
    _pruneHarDrafts();
    draft.url = url;
    draft.method = method;
    draft.requestHeaders = _clipHeaders(headers);
    draft.postData = clipNullableText(postData, _maxHarPostDataChars);
    draft.startedAt = startedAt;
  }

  void recordHarResponse({
    required String requestId,
    required int status,
    required String statusText,
    required String mimeType,
    required Map<String, Object?> headers,
    int? bodySize,
  }) {
    if (_closed) return;
    final draft = _harDrafts[requestId];
    if (draft == null) return;
    draft.status = status;
    draft.statusText = statusText;
    draft.mimeType = mimeType;
    draft.responseHeaders = _clipHeaders(headers);
    draft.bodySize = bodySize ?? -1;
  }

  void recordHarFinished(String requestId, DateTime finishedAt) {
    if (_closed) return;
    final draft = _harDrafts[requestId];
    if (draft == null) return;
    draft.finishedAt = finishedAt;
  }

  void recordHarFailed(String requestId, String errorText, DateTime failedAt) {
    if (_closed) return;
    final draft = _harDrafts[requestId];
    if (draft == null) return;
    draft.errorText = errorText;
    draft.finishedAt = failedAt;
  }

  void evictHarDraft(String requestId) {
    if (_closed) return;
    _harDrafts.remove(requestId);
  }

  void _appendJsonLine(
    StringBuffer buffer,
    Map<String, Object?> event,
    String streamName,
  ) {
    if (!_ready || _closed) return;
    try {
      final line = jsonEncode(event);
      if (line.length > _maxJsonlEventChars) {
        _logBufferDropOnce(streamName, 'oversized event');
        return;
      }
      if (buffer.length + line.length + 1 > _maxJsonlPendingChars) {
        _logBufferDropOnce(streamName, 'pending buffer full');
        return;
      }
      buffer.writeln(line);
    } catch (error, stack) {
      silentLog(
        'web_reverse_artifacts',
        'encode $streamName event',
        error,
        stack,
      );
    }
  }

  void _logBufferDropOnce(String streamName, String reason) {
    final key = '$streamName:$reason';
    if (!_reportedBufferDrops.add(key)) return;
    silentLog('web_reverse_artifacts', 'drop $streamName event', reason);
  }

  void _flush() {
    if (!_ready) return;
    _flushBuffer(_networkBuf, _networkSink, 'network');
    _flushBuffer(_consoleBuf, _consoleSink, 'console');
  }

  void _flushBuffer(StringBuffer buffer, IOSink? sink, String streamName) {
    if (buffer.isEmpty) return;
    final pending = buffer.toString();
    buffer.clear();
    _reportedBufferDrops.removeWhere((key) => key.startsWith('$streamName:'));
    try {
      sink?.write(pending);
    } catch (error, stack) {
      silentLog('web_reverse_artifacts', 'flush $streamName', error, stack);
    }
  }

  /// 将 HAR 草稿合成为 HAR 1.2 文档并写到 `<rootDir>/har/<timestamp>.har`。
  /// 返回写出的文件路径；失败返回 null。
  Future<String?> exportHar() async {
    if (!_ready || _closed) return null;
    final entries = <Map<String, Object?>>[];
    for (final draft in _harDrafts.values) {
      if (draft.url.isEmpty) continue;
      final startedAt = draft.startedAt ?? DateTime.now().toUtc();
      final finishedAt = draft.finishedAt ?? startedAt;
      final duration = finishedAt.difference(startedAt).inMilliseconds;
      entries.add(<String, Object?>{
        'startedDateTime': startedAt.toUtc().toIso8601String(),
        'time': duration < 0 ? 0 : duration,
        'request': <String, Object?>{
          'method': draft.method,
          'url': draft.url,
          'httpVersion': 'HTTP/1.1',
          'cookies': const <Object?>[],
          'headers': _harHeaders(draft.requestHeaders),
          'queryString': const <Object?>[],
          if (draft.postData != null && draft.postData!.isNotEmpty)
            'postData': <String, Object?>{
              'mimeType': 'application/octet-stream',
              'text': draft.postData,
            },
          'headersSize': -1,
          'bodySize': draft.postData?.length ?? -1,
        },
        'response': <String, Object?>{
          'status': draft.status,
          'statusText': draft.statusText,
          'httpVersion': 'HTTP/1.1',
          'cookies': const <Object?>[],
          'headers': _harHeaders(draft.responseHeaders),
          'content': <String, Object?>{
            'size': draft.bodySize,
            'mimeType': draft.mimeType,
          },
          'redirectURL': '',
          'headersSize': -1,
          'bodySize': draft.bodySize,
          if (draft.errorText != null) '_error': draft.errorText,
        },
        'cache': const <String, Object?>{},
        'timings': <String, Object?>{
          'send': 0,
          'wait': duration < 0 ? 0 : duration,
          'receive': 0,
        },
      });
    }
    final har = <String, Object?>{
      'log': <String, Object?>{
        'version': '1.2',
        'creator': <String, Object?>{
          'name': 'OpenHand WebReverseExpert',
          'version': '1.0.0',
        },
        'pages': const <Object?>[],
        'entries': entries,
      },
    };
    try {
      final ts = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
      final path = '$rootDir/har/$ts.har';
      await File(path).writeAsString(prettyPrintJson(har));
      return path;
    } catch (error, stack) {
      silentLog('web_reverse_artifacts', 'exportHar', error, stack);
      return null;
    }
  }

  Future<void> close() {
    _closed = true;
    final existing = _closeFuture;
    if (existing != null) return existing;
    final closing = _performClose();
    _closeFuture = closing;
    return closing;
  }

  Future<void> _performClose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _flush();
    final networkSink = _networkSink;
    final consoleSink = _consoleSink;
    _networkSink = null;
    _consoleSink = null;
    _ready = false;
    _networkBuf.clear();
    _consoleBuf.clear();
    _reportedBufferDrops.clear();
    _harDrafts.clear();
    await Future.wait<bool>(<Future<bool>>[
      _closeSink(networkSink, 'network'),
      _closeSink(consoleSink, 'console'),
    ]);
  }

  Future<bool> _closeSink(IOSink? sink, String streamName) {
    if (sink == null) return Future<bool>.value(true);
    // IOSink.close flushes buffered data before releasing the file handle.
    return runAsyncCleanupBounded(
      sink.close,
      onError: (error, stack) => silentLog(
        'web_reverse_artifacts',
        'close $streamName sink',
        error,
        stack,
      ),
    );
  }

  static List<Map<String, Object?>> _harHeaders(Map<String, Object?>? headers) {
    if (headers == null) return const <Map<String, Object?>>[];
    return headers.entries
        .map((e) => <String, Object?>{'name': e.key, 'value': '${e.value}'})
        .toList(growable: false);
  }

  void _pruneHarDrafts() {
    while (_harDrafts.length > _maxHarDrafts) {
      _harDrafts.remove(_harDrafts.keys.first);
    }
  }

  static Map<String, Object?> _clipHeaders(Map<String, Object?> headers) {
    final out = <String, Object?>{};
    for (final entry in headers.entries.take(_maxHarHeaders)) {
      out[entry.key] = clipText('${entry.value}', _maxHarHeaderValueChars);
    }
    return out;
  }
}

class _HarEntryDraft {
  _HarEntryDraft({required this.requestId});

  final String requestId;
  String url = '';
  String method = 'GET';
  Map<String, Object?>? requestHeaders;
  String? postData;
  DateTime? startedAt;
  DateTime? finishedAt;
  int status = 0;
  String statusText = '';
  String mimeType = '';
  Map<String, Object?>? responseHeaders;
  int bodySize = -1;
  String? errorText;
}
