import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app/support/silent_log.dart';
import 'web_reverse_cdp_client.dart';

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
  void cancel() => _cancelled = true;
  bool get isCancelled => _cancelled;

  Future<List<HeadlessBatchUrlResult>> run() async {
    final results = <HeadlessBatchUrlResult>[];
    await Directory(outputDir).create(recursive: true);
    for (var i = 0; i < urls.length; i++) {
      if (_cancelled) {
        results.add(HeadlessBatchUrlResult(
          url: urls[i],
          ok: false,
          error: 'cancelled',
        ));
        _emit(i, urls[i], HeadlessBatchPhase.cancelled);
        continue;
      }
      final url = urls[i].trim();
      _emit(i, url, HeadlessBatchPhase.starting);
      try {
        final r = await _runOne(i, url);
        results.add(r);
        _emit(i, url, r.ok ? HeadlessBatchPhase.done : HeadlessBatchPhase.failed,
            message: r.error);
      } catch (e, st) {
        silentLog('web_reverse_headless_batch', 'run', e, st);
        results.add(HeadlessBatchUrlResult(url: url, ok: false, error: '$e'));
        _emit(i, url, HeadlessBatchPhase.failed, message: '$e');
      }
    }
    return results;
  }

  void _emit(int index, String url, HeadlessBatchPhase phase,
      {String? message}) {
    final cb = onProgress;
    if (cb == null) return;
    try {
      cb(HeadlessBatchProgress(
        index: index,
        total: urls.length,
        url: url,
        phase: phase,
        message: message,
      ));
    } catch (e, st) {
      silentLog('web_reverse_headless_batch', '_emit', e, st);
    }
  }

  Future<HeadlessBatchUrlResult> _runOne(int index, String url) async {
    String? targetId;
    String? sessionId;
    StreamSubscription<CdpEvent>? sub;
    final networkResponses = <Map<String, Object?>>[];
    final consoleEntries = <Map<String, Object?>>[];
    final loadCompleter = Completer<void>();
    try {
      final created = await cdp.send(
        'Target.createTarget',
        params: <String, Object?>{
          'url': 'about:blank',
          'background': true,
        },
        timeout: const Duration(seconds: 10),
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
        params: <String, Object?>{
          'targetId': targetId,
          'flatten': true,
        },
        timeout: const Duration(seconds: 10),
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
            break;
          case 'Network.responseReceived':
            final resp = ev.params['response'];
            if (resp is Map) {
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
            break;
          case 'Network.loadingFailed':
            networkResponses.add(<String, Object?>{
              'request_id': ev.params['requestId'],
              'failed': true,
              'error_text': ev.params['errorText'],
              'type': ev.params['type'],
            });
            break;
          case 'Runtime.consoleAPICalled':
          case 'Log.entryAdded':
            final args = ev.params['args'];
            final text = args is List
                ? args
                    .whereType<Map>()
                    .map((m) => m['value']?.toString() ?? m['description']?.toString() ?? '')
                    .where((s) => s.isNotEmpty)
                    .join(' ')
                : ev.params['entry'] is Map
                    ? '${(ev.params['entry'] as Map)['text']}'
                    : '';
            consoleEntries.add(<String, Object?>{
              'level': ev.params['type']?.toString() ??
                  (ev.params['entry'] is Map
                      ? '${(ev.params['entry'] as Map)['level']}'
                      : 'log'),
              'text': text,
              'ts': DateTime.now().toIso8601String(),
            });
            break;
        }
      });

      await cdp.send('Page.enable',
          sessionId: sessionId, timeout: const Duration(seconds: 5));
      if (captureNetwork) {
        await cdp.send('Network.enable',
            sessionId: sessionId, timeout: const Duration(seconds: 5));
      }
      if (captureConsole) {
        await cdp.send('Runtime.enable',
            sessionId: sessionId, timeout: const Duration(seconds: 5));
        await cdp.send('Log.enable',
            sessionId: sessionId, timeout: const Duration(seconds: 5));
      }

      _emit(index, url, HeadlessBatchPhase.navigating);
      await cdp.send('Page.navigate',
          params: <String, Object?>{'url': url},
          sessionId: sessionId,
          timeout: const Duration(seconds: 10));

      _emit(index, url, HeadlessBatchPhase.waitingLoad);
      try {
        await loadCompleter.future.timeout(perUrlTimeout);
      } on TimeoutException {
        // 即使 load 没 fire 也继续把已采集到的东西落盘。
      }
      if (settleAfterLoad > Duration.zero) {
        await Future<void>.delayed(settleAfterLoad);
      }

      final dirName = _sanitizeDir(url, index);
      final perDir = Directory('$outputDir/$dirName');
      await perDir.create(recursive: true);

      if (captureNetwork) {
        await File('${perDir.path}/network.json').writeAsString(
            const JsonEncoder.withIndent('  ')
                .convert(<String, Object?>{'url': url, 'responses': networkResponses}));
      }
      if (captureConsole) {
        await File('${perDir.path}/console.json').writeAsString(
            const JsonEncoder.withIndent('  ')
                .convert(<String, Object?>{'url': url, 'entries': consoleEntries}));
      }

      String? screenshotPath;
      if (captureScreenshot && !_cancelled) {
        _emit(index, url, HeadlessBatchPhase.capturingScreenshot);
        try {
          final shot = await cdp.send('Page.captureScreenshot',
              params: <String, Object?>{'format': 'png'},
              sessionId: sessionId,
              timeout: const Duration(seconds: 10));
          final data = shot['data'];
          if (data is String && data.isNotEmpty) {
            final path = '${perDir.path}/screenshot.png';
            await File(path).writeAsBytes(base64Decode(data));
            screenshotPath = path;
          }
        } catch (e, st) {
          silentLog('web_reverse_headless_batch', 'captureScreenshot', e, st);
        }
      }

      return HeadlessBatchUrlResult(
        url: url,
        ok: true,
        outDir: perDir.path,
        networkCount: networkResponses.length,
        consoleCount: consoleEntries.length,
        screenshotPath: screenshotPath,
      );
    } catch (e, st) {
      silentLog('web_reverse_headless_batch', '_runOne', e, st);
      return HeadlessBatchUrlResult(url: url, ok: false, error: '$e');
    } finally {
      await sub?.cancel();
      if (targetId != null) {
        try {
          await cdp.send('Target.closeTarget',
              params: <String, Object?>{'targetId': targetId},
              timeout: const Duration(seconds: 5));
        } catch (e, st) {
          silentLog('web_reverse_headless_batch', 'closeTarget', e, st);
        }
      }
    }
  }

  static String _sanitizeDir(String url, int index) {
    final cleaned = url
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final clipped = cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
    final idx = (index + 1).toString().padLeft(3, '0');
    return '${idx}_$clipped';
  }
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
    this.screenshotPath,
    this.error,
  });

  final String url;
  final bool ok;
  final String? outDir;
  final int networkCount;
  final int consoleCount;
  final String? screenshotPath;
  final String? error;
}
