import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/support/silent_log.dart';
import '../db/atomic_file_operations.dart';
import '../util/async_concurrency.dart';
import '../util/bounded_base64.dart';
import '../util/bounded_file_io.dart';
import '../util/byte_size_format.dart';
import '../util/timer_safety.dart';

class OpenHandVideoThumbnailManager {
  static const int _failedCacheLimit = 512;
  static const int _maxPendingCaptures = 32;
  static final OpenHandAsyncSemaphore _semaphore = OpenHandAsyncSemaphore(
    1,
    maxAllowedPermits: 1,
    maxWaiters: _maxPendingCaptures,
  );
  static final Set<String> _failed = <String>{};

  static String thumbnailPathFor(String videoPath) => '$videoPath.thumb.png';

  static bool isMarkedFailed(String videoPath) {
    if (!_failed.remove(videoPath)) return false;
    _failed.add(videoPath);
    return true;
  }

  static void _markFailed(String videoPath) {
    _failed.remove(videoPath);
    _failed.add(videoPath);
    while (_failed.length > _failedCacheLimit) {
      _failed.remove(_failed.first);
    }
  }

  static Future<bool> _acquireSlot(
    Duration timeout, {
    required Future<void> cancelSignal,
  }) => _semaphore.acquireWithin(timeout, cancelSignal: cancelSignal);

  static void _releaseSlot() => _semaphore.release();
}

class OpenHandVideoThumbnailCapture extends StatefulWidget {
  const OpenHandVideoThumbnailCapture({
    super.key,
    required this.videoPath,
    required this.mimeType,
    required this.onResult,
  });

  final String videoPath;
  final String mimeType;
  final void Function(String? thumbnailPath) onResult;

  @override
  State<OpenHandVideoThumbnailCapture> createState() =>
      _OpenHandVideoThumbnailCaptureState();
}

class _OpenHandVideoThumbnailCaptureState
    extends State<OpenHandVideoThumbnailCapture>
    with WidgetsBindingObserver {
  static const Duration _captureTimeout = Duration(seconds: 18);
  static const Duration _queueTimeout = Duration(seconds: 30);
  static const Duration _fileOperationTimeout = Duration(seconds: 5);
  static const int _maxThumbnailBytes = kBytesPerMiB;

  WebViewController? _controller;
  String? _temporaryHtmlPath;
  bool _slotHeld = false;
  bool _done = false;
  bool _watchdogPausedForLifecycle = false;
  final Completer<void> _captureCancellation = Completer<void>();
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_done) return;
    if (state != AppLifecycleState.resumed) {
      if (_watchdog != null && _watchdog!.isActive) {
        _watchdog!.cancel();
        _watchdog = null;
        _watchdogPausedForLifecycle = true;
      }
      return;
    }
    if (_watchdogPausedForLifecycle && _watchdog == null) {
      _watchdogPausedForLifecycle = false;
      _watchdog = startSafeTimer(_captureTimeout, () {
        if (!_done) _finish(null);
      });
    }
  }

  Future<void> _start() async {
    var acquired = false;
    try {
      acquired = await OpenHandVideoThumbnailManager._acquireSlot(
        _queueTimeout,
        cancelSignal: _captureCancellation.future,
      );
    } catch (error, stack) {
      silentLog('video_thumbnail', '视频封面取号失败', error, stack);
      _finish(null, markFailed: false);
      return;
    }
    if (!acquired) {
      if (!_done &&
          mounted &&
          !await isCancelSignalCompleted(_captureCancellation.future)) {
        _finish(null, markFailed: false);
      }
      return;
    }
    if (_done || !mounted) {
      OpenHandVideoThumbnailManager._releaseSlot();
      return;
    }
    _slotHeld = true;
    _watchdog = startSafeTimer(_captureTimeout, () {
      if (!_done) _finish(null);
    });
    try {
      final thumbnailPath = OpenHandVideoThumbnailManager.thumbnailPathFor(
        widget.videoPath,
      );
      try {
        final alreadyGenerated = await File(
          thumbnailPath,
        ).exists().timeout(_fileOperationTimeout);
        if (_done || !mounted) return;
        if (alreadyGenerated) {
          _finish(thumbnailPath);
          return;
        }
      } catch (error, stack) {
        silentLog('video_thumbnail', '检查视频封面缓存失败', error, stack);
      }
      if (_done || !mounted) return;
      final temporaryFile = File(
        p.join(
          p.dirname(widget.videoPath),
          '.openhand_thumb_capture_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}.html',
        ),
      );
      _temporaryHtmlPath = temporaryFile.path;
      await writeTemporaryFileTextBounded(
        temporaryFile,
        _buildCaptureHtml(),
        timeout: _fileOperationTimeout,
        onSecondaryError: (error, stack) =>
            silentLog('video_thumbnail', '清理视频封面临时页面失败', error, stack),
      );
      if (_done || !mounted) {
        _deleteTemporaryHtmlInBackground();
        return;
      }
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'OpenHandThumb',
        onMessageReceived: _onMessage,
      );
      if (!Platform.isMacOS) {
        await controller.setBackgroundColor(Colors.transparent);
      }
      _controller = controller;
      await awaitWithCancelSignal<bool>(
        controller.loadFile(temporaryFile.path).then((_) => true),
        cancelSignal: _captureCancellation.future,
      );
      if (_done || !mounted) return;
      setState(() {});
    } catch (error, stack) {
      if (_done) return;
      silentLog('video_thumbnail', '初始化视频封面失败', error, stack);
      _finish(null);
    }
  }

  void _onMessage(JavaScriptMessage message) {
    if (_done) return;
    final value = message.message;
    if (value.startsWith('error')) {
      _finish(null);
      return;
    }
    const marker = 'base64,';
    final markerIndex = value.indexOf(marker);
    if (markerIndex < 0) {
      _finish(null);
      return;
    }
    unawaited(_persistThumbnail(value.substring(markerIndex + marker.length)));
  }

  Future<void> _persistThumbnail(String encoded) async {
    try {
      final bytes = decodeBase64Bounded(
        encoded,
        maxDecodedBytes: _maxThumbnailBytes,
      );
      if (_done || !mounted) return;
      final outputPath = OpenHandVideoThumbnailManager.thumbnailPathFor(
        widget.videoPath,
      );
      final outputFile = File(outputPath);
      if (!await outputFile.exists().timeout(_fileOperationTimeout)) {
        await writeBytesFileAtomically(outputFile, bytes);
      }
      _finish(outputPath);
    } catch (error, stack) {
      if (!_done) {
        silentLog('video_thumbnail', '写入视频封面失败', error, stack);
      }
      _finish(null);
    }
  }

  void _finish(String? path, {bool markFailed = true}) {
    if (_done) return;
    _done = true;
    _watchdog?.cancel();
    if (!_captureCancellation.isCompleted) {
      _captureCancellation.complete();
    }
    if (path == null && markFailed) {
      OpenHandVideoThumbnailManager._markFailed(widget.videoPath);
    }
    _deleteTemporaryHtmlInBackground();
    if (_slotHeld) {
      _slotHeld = false;
      OpenHandVideoThumbnailManager._releaseSlot();
    }
    widget.onResult(path);
  }

  void _deleteTemporaryHtmlInBackground() {
    final path = _temporaryHtmlPath;
    _temporaryHtmlPath = null;
    if (path == null) return;
    unawaited(_deleteTemporaryHtml(path));
  }

  static Future<void> _deleteTemporaryHtml(String path) async {
    try {
      final file = File(path);
      if (await file.exists().timeout(_fileOperationTimeout)) {
        await file.delete().timeout(_fileOperationTimeout);
      }
    } catch (error, stack) {
      silentLog('video_thumbnail', '删除视频封面临时文件失败', error, stack);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_captureCancellation.isCompleted) {
      _captureCancellation.complete();
    }
    if (!_done) {
      _done = true;
      _watchdog?.cancel();
      _deleteTemporaryHtmlInBackground();
      if (_slotHeld) {
        _slotHeld = false;
        OpenHandVideoThumbnailManager._releaseSlot();
      }
    }
    super.dispose();
  }

  String _buildCaptureHtml() {
    final source = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(Uri.file(widget.videoPath).toString());
    final mimeType = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(widget.mimeType);
    return '''
<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:#000;width:100%;height:100%;overflow:hidden}video{position:fixed;left:0;top:0;width:32px;height:32px;opacity:0.01;pointer-events:none}canvas{display:none}</style></head><body>
<video id="v" muted autoplay playsinline preload="auto" disableRemotePlayback><source src="$source" type="$mimeType"></video>
<canvas id="c"></canvas>
<script>(function(){
var v=document.getElementById('v');var c=document.getElementById('c');
var captured=false;
function post(m){try{if(window.OpenHandThumb&&window.OpenHandThumb.postMessage){window.OpenHandThumb.postMessage(String(m));}}catch(_){}}
function tryCapture(reason){
  if(captured)return false;
  var w=v.videoWidth,h=v.videoHeight;
  if(!w||!h)return false;
  try{
    var scale=Math.min(1,480/w,480/h);
    var tw=Math.max(1,Math.round(w*scale));
    var th=Math.max(1,Math.round(h*scale));
    c.width=tw;c.height=th;
    var ctx=c.getContext('2d');
    ctx.drawImage(v,0,0,tw,th);
    var url=c.toDataURL('image/png');
    if(!url||url.length<64)return false;
    captured=true;
    post(url);
    return true;
  }catch(e){return false;}
}
function safeSeek(t){try{v.currentTime=t;}catch(_){}}
function armRVFC(){
  if(captured)return;
  if(typeof v.requestVideoFrameCallback==='function'){
    try{v.requestVideoFrameCallback(function(){tryCapture('rvfc');if(!captured){v.requestVideoFrameCallback(function(){tryCapture('rvfc2');});}});}catch(_){}
  }
}
v.addEventListener('loadedmetadata',function(){
  armRVFC();
  var playback;
  try{v.muted=true;v.volume=0;playback=v.play();}catch(_){playback=null;}
  if(playback&&playback.then){
    playback.then(function(){
      setTimeout(function(){
        tryCapture('after_play');
        try{v.pause();}catch(_){}
        safeSeek(Math.min(0.05,(v.duration||0)));
      },180);
    }).catch(function(){safeSeek(Math.min(0.05,(v.duration||0)));});
  }else{safeSeek(Math.min(0.05,(v.duration||0)));}
});
v.addEventListener('seeked',function(){tryCapture('seeked');});
v.addEventListener('canplay',function(){armRVFC();tryCapture('canplay');});
v.addEventListener('canplaythrough',function(){tryCapture('canplaythrough');});
var attempts=0;
var poll=setInterval(function(){
  attempts++;
  if(captured||attempts>40){clearInterval(poll);return;}
  tryCapture('poll'+attempts);
},250);
v.addEventListener('error',function(){post('error:video_load');});
setTimeout(function(){if(!captured){clearInterval(poll);post('error:timeout');}},14000);
})();</script>
</body></html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return SizedBox(
      width: 32,
      height: 32,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.01,
          child: WebViewWidget(controller: controller),
        ),
      ),
    );
  }
}
