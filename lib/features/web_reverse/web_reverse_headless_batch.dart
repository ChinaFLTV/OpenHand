import 'dart:async';
import 'dart:io';

import '../../app/support/silent_log.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_base64.dart';
import '../../shared/util/bounded_directory_io.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/path_safety.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_cdp_client.dart';

/// 目标创建、附着与导航等 I/O 类 CDP 命令。
const Duration _kHeadlessCdpIoTimeout = Duration(seconds: 10);

/// 会话内的常规配置与求值类 CDP 命令。
const Duration _kHeadlessCdpCommandTimeout = Duration(seconds: 5);

const int kWebReverseHeadlessBatchMaxUrls = 50;
const int kWebReverseHeadlessBatchMaxNetworkEventsPerUrl = 1500;
const int kWebReverseHeadlessBatchMaxConsoleEventsPerUrl = 1000;
const int kWebReverseHeadlessBatchMaxConsoleTextChars = 4 * kBytesPerKiB;
const int _kHeadlessMaxScreenshotDecodedBytes = 48 * kBytesPerMiB;
const int _kHeadlessMaxScreenshotResponseCharacters = 65 * kBytesPerMiB;

/// Headless 批量采集：复用现有 [WebReverseCdpClient]，按 URL 列表逐个建一个
/// 后台 Page target，做最小可用的事件采集（network response 列表 / console /
/// 截图），完成后落盘并关闭 target。完全运行在现有浏览器进程里，不另起进程，
/// 因此目标站点能复用现有 cookie / hook / 拦截规则。
///
/// 设计上故意不复用 controller 的 `_PerTargetBuffer`，避免污染交互式 dashboard
/// 的现场；批量采集是一次性命令式流水线，跑完即丢。
class WebReverseHeadlessBatch {
  WebReverseHeadlessBatch({
    required this.cdp,
    required this.urls,
    required this.outputDir,
    this.perUrlTimeout = const Duration(seconds: 25),
    this.settleAfterLoad = const Duration(milliseconds: 1200),
    this.captureScreenshot = true,
    this.captureNetwork = true,
    this.captureConsole = true,
    this.onProgress,
  });

  final WebReverseCdpClient cdp;
  final List<String> urls;
  final String outputDir;
  final Duration perUrlTimeout;
  final Duration settleAfterLoad;
  final bool captureScreenshot;
  final bool captureNetwork;
  final bool captureConsole;
  final void Function(HeadlessBatchProgress progress)? onProgress;

  bool _cancelled = false;
  final Completer<void> _cancelCompleter = Completer<void>();

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_cancelCompleter.isCompleted) _cancelCompleter.complete();
  }

  bool get isCancelled => _cancelled;

  Future<List<HeadlessBatchUrlResult>> run() async {
    final results = <HeadlessBatchUrlResult>[];
    final cappedUrls = stringListFromValue(
      urls,
    ).where(_isHttpUrl).take(kWebReverseHeadlessBatchMaxUrls).toList();
    await createDirectoryBounded(Directory(outputDir));
    for (var i = 0; i < cappedUrls.length; i++) {
      if (_cancelled) {
        results.add(
          HeadlessBatchUrlResult(
            url: cappedUrls[i],
            ok: false,
            error: 'cancelled',
          ),
        );
        _emit(
          i,
          cappedUrls[i],
          HeadlessBatchPhase.cancelled,
          cappedUrls.length,
        );
        continue;
      }
      final url = cappedUrls[i];
      _emit(i, url, HeadlessBatchPhase.starting, cappedUrls.length);
      try {
        final r = await _runOne(i, url, cappedUrls.length);
        results.add(r);
        _emit(
          i,
          url,
          r.ok ? HeadlessBatchPhase.done : HeadlessBatchPhase.failed,
          cappedUrls.length,
          message: r.error,
        );
      } catch (e, st) {
        silentLog('web_reverse_headless_batch', '执行批量采集', e, st);
        results.add(HeadlessBatchUrlResult(url: url, ok: false, error: '$e'));
        _emit(
          i,
          url,
          HeadlessBatchPhase.failed,
          cappedUrls.length,
          message: '$e',
        );
      }
    }
    return results;
  }

  void _emit(
    int index,
    String url,
    HeadlessBatchPhase phase,
    int total, {
    String? message,
  }) {
    final cb = onProgress;
    if (cb == null) return;
    try {
      cb(
        HeadlessBatchProgress(
          index: index,
          total: total,
          url: url,
          phase: phase,
          message: message,
        ),
      );
    } catch (e, st) {
      silentLog('web_reverse_headless_batch', '发送批量采集事件', e, st);
    }
  }

  Future<HeadlessBatchUrlResult> _runOne(
    int index,
    String url,
    int total,
  ) async {
    String? targetId;
    String? sessionId;
    StreamSubscription<CdpEvent>? sub;
    final networkResponses = <Map<String, Object?>>[];
    final consoleEntries = <Map<String, Object?>>[];
    var networkDropped = 0;
    var consoleDropped = 0;
    final loadCompleter = Completer<void>();
    HeadlessBatchUrlResult cancelledResult() => HeadlessBatchUrlResult(
      url: url,
      ok: false,
      error: 'cancelled',
      networkCount: networkResponses.length,
      consoleCount: consoleEntries.length,
      networkDropped: networkDropped,
      consoleDropped: consoleDropped,
    );
    try {
      final created = await cdp.send(
        'Target.createTarget',
        params: <String, Object?>{'url': 'about:blank', 'background': true},
        timeout: _kHeadlessCdpIoTimeout,
      );
      targetId = created['targetId'] as String?;
      if (targetId == null) {
        return HeadlessBatchUrlResult(
          url: url,
          ok: false,
          error: 'Target.createTarget did not return targetId',
        );
      }
      final attached = await cdp.send(
        'Target.attachToTarget',
        params: <String, Object?>{'targetId': targetId, 'flatten': true},
        timeout: _kHeadlessCdpIoTimeout,
      );
      sessionId = attached['sessionId'] as String?;
      if (sessionId == null) {
        return HeadlessBatchUrlResult(
          url: url,
          ok: false,
          error: 'attachToTarget did not return sessionId',
        );
      }

      sub = cdp.events.listen((ev) {
        if (ev.sessionId != sessionId) return;
        switch (ev.method) {
          case 'Page.loadEventFired':
            if (!loadCompleter.isCompleted) loadCompleter.complete();
          case 'Network.responseReceived':
            final resp = ev.params['response'];
            if (resp is Map) {
              if (networkResponses.length >=
                  kWebReverseHeadlessBatchMaxNetworkEventsPerUrl) {
                networkDropped++;
                break;
              }
              final r = resp.cast<String, Object?>();
              networkResponses.add(<String, Object?>{
                'request_id': ev.params['requestId'],
                'loader_id': ev.params['loaderId'],
                'type': ev.params['type'],
                'url': r['url'],
                'status': r['status'],
                'status_text': r['statusText'],
                'mime_type': r['mimeType'],
                'remote_ip': r['remoteIPAddress'],
                'remote_port': r['remotePort'],
                'protocol': r['protocol'],
                'from_disk_cache': r['fromDiskCache'],
                'response_headers': r['headers'],
                'encoded_len': r['encodedDataLength'],
              });
            }
          case 'Network.loadingFailed':
            if (networkResponses.length >=
                kWebReverseHeadlessBatchMaxNetworkEventsPerUrl) {
              networkDropped++;
              break;
            }
            networkResponses.add(<String, Object?>{
              'request_id': ev.params['requestId'],
              'failed': true,
              'error_text': ev.params['errorText'],
              'type': ev.params['type'],
            });
          case 'Runtime.consoleAPICalled':
          case 'Log.entryAdded':
            if (consoleEntries.length >=
                kWebReverseHeadlessBatchMaxConsoleEventsPerUrl) {
              consoleDropped++;
              break;
            }
            final args = ev.params['args'];
            final text = args is List
                ? args
                      .whereType<Map>()
                      .map(
                        (m) =>
                            m['value']?.toString() ??
                            m['description']?.toString() ??
                            '',
                      )
                      .where((s) => s.isNotEmpty)
                      .join(' ')
                : ev.params['entry'] is Map
                ? '${(ev.params['entry'] as Map)['text']}'
                : '';
            final clippedText = clipText(
              text,
              kWebReverseHeadlessBatchMaxConsoleTextChars,
            );
            consoleEntries.add(<String, Object?>{
              'level':
                  ev.params['type']?.toString() ??
                  (ev.params['entry'] is Map
                      ? '${(ev.params['entry'] as Map)['level']}'
                      : 'log'),
              'text': clippedText,
              'text_truncated':
                  text.length > kWebReverseHeadlessBatchMaxConsoleTextChars,
              'ts': DateTime.now().toIso8601String(),
            });
        }
      });

      await cdp.send(
        'Page.enable',
        sessionId: sessionId,
        timeout: _kHeadlessCdpCommandTimeout,
      );
      if (captureNetwork) {
        await cdp.send(
          'Network.enable',
          sessionId: sessionId,
          timeout: _kHeadlessCdpCommandTimeout,
        );
      }
      if (captureConsole) {
        await cdp.send(
          'Runtime.enable',
          sessionId: sessionId,
          timeout: _kHeadlessCdpCommandTimeout,
        );
        await cdp.send(
          'Log.enable',
          sessionId: sessionId,
          timeout: _kHeadlessCdpCommandTimeout,
        );
      }

      _emit(index, url, HeadlessBatchPhase.navigating, total);
      await cdp.send(
        'Page.navigate',
        params: <String, Object?>{'url': url},
        sessionId: sessionId,
        timeout: _kHeadlessCdpIoTimeout,
      );

      _emit(index, url, HeadlessBatchPhase.waitingLoad, total);
      try {
        await Future.any<void>([
          loadCompleter.future.timeout(perUrlTimeout),
          _cancelCompleter.future,
        ]);
      } on TimeoutException {
        // 即使 load 没 fire 也继续把已采集到的东西落盘。
      }
      if (_cancelled) return cancelledResult();
      if (settleAfterLoad > Duration.zero) {
        await Future.any<void>([
          Future<void>.delayed(settleAfterLoad),
          _cancelCompleter.future,
        ]);
      }
      if (_cancelled) return cancelledResult();

      final dirName = _sanitizeDir(url, index);
      final perDir = Directory('$outputDir/$dirName');
      await createDirectoryBounded(perDir);

      if (captureNetwork) {
        await writeFileAtomically(
          File('${perDir.path}/network.json'),
          prettyPrintJson(<String, Object?>{
            'url': url,
            'captured': networkResponses.length,
            'dropped': networkDropped,
            'truncated':
                networkDropped > 0 ||
                networkResponses.length >=
                    kWebReverseHeadlessBatchMaxNetworkEventsPerUrl,
            'responses': networkResponses,
          }),
        );
      }
      if (captureConsole) {
        await writeFileAtomically(
          File('${perDir.path}/console.json'),
          prettyPrintJson(<String, Object?>{
            'url': url,
            'captured': consoleEntries.length,
            'dropped': consoleDropped,
            'truncated':
                consoleDropped > 0 ||
                consoleEntries.length >=
                    kWebReverseHeadlessBatchMaxConsoleEventsPerUrl,
            'entries': consoleEntries,
          }),
        );
      }

      String? screenshotPath;
      if (captureScreenshot && !_cancelled) {
        _emit(index, url, HeadlessBatchPhase.capturingScreenshot, total);
        try {
          final shot = await cdp.send(
            'Page.captureScreenshot',
            params: <String, Object?>{'format': 'png'},
            sessionId: sessionId,
            timeout: _kHeadlessCdpIoTimeout,
            maxResponseCharacters: _kHeadlessMaxScreenshotResponseCharacters,
          );
          final data = shot['data'];
          if (data is String && data.isNotEmpty) {
            final path = '${perDir.path}/screenshot.png';
            final bytes = decodeBase64Bounded(
              data,
              maxDecodedBytes: _kHeadlessMaxScreenshotDecodedBytes,
            );
            await writeBytesFileAtomically(File(path), bytes);
            screenshotPath = path;
          }
        } catch (e, st) {
          silentLog('web_reverse_headless_batch', '截取无头页面截图', e, st);
        }
      }

      return HeadlessBatchUrlResult(
        url: url,
        ok: true,
        outDir: perDir.path,
        networkCount: networkResponses.length,
        consoleCount: consoleEntries.length,
        networkDropped: networkDropped,
        consoleDropped: consoleDropped,
        screenshotPath: screenshotPath,
      );
    } catch (e, st) {
      silentLog('web_reverse_headless_batch', '执行单项批量采集', e, st);
      return HeadlessBatchUrlResult(url: url, ok: false, error: '$e');
    } finally {
      await cancelStreamSubscriptionBounded<CdpEvent>(
        sub,
        onError: (error, stack) =>
            silentLog('web_reverse_headless_batch', '取消目标事件订阅', error, stack),
      );
      if (targetId != null) {
        try {
          await cdp.send(
            'Target.closeTarget',
            params: <String, Object?>{'targetId': targetId},
            timeout: _kHeadlessCdpCommandTimeout,
          );
        } catch (e, st) {
          silentLog('web_reverse_headless_batch', '关闭无头页面目标', e, st);
        }
      }
    }
  }

  static String _sanitizeDir(String url, int index) {
    final cleaned = url.replaceAll(RegExp(r'^https?://'), '');
    final clipped = sanitizePortableFileNamePart(
      cleaned,
      fallback: '',
      maxCharacters: 80,
    );
    final idx = (index + 1).toString().padLeft(3, '0');
    return '${idx}_$clipped';
  }

  static bool _isHttpUrl(String url) =>
      url.startsWith('http://') || url.startsWith('https://');
}

enum HeadlessBatchPhase {
  starting,
  navigating,
  waitingLoad,
  capturingScreenshot,
  done,
  failed,
  cancelled,
}

class HeadlessBatchProgress {
  const HeadlessBatchProgress({
    required this.index,
    required this.total,
    required this.url,
    required this.phase,
    this.message,
  });

  final int index;
  final int total;
  final String url;
  final HeadlessBatchPhase phase;
  final String? message;
}

class HeadlessBatchUrlResult {
  const HeadlessBatchUrlResult({
    required this.url,
    required this.ok,
    this.outDir,
    this.networkCount = 0,
    this.consoleCount = 0,
    this.networkDropped = 0,
    this.consoleDropped = 0,
    this.screenshotPath,
    this.error,
  });

  final String url;
  final bool ok;
  final String? outDir;
  final int networkCount;
  final int consoleCount;
  final int networkDropped;
  final int consoleDropped;
  final String? screenshotPath;
  final String? error;
}
