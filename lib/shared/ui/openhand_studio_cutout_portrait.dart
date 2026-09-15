import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../util/async_concurrency.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';

/// SkillHub 角色立绘：浅色拼图底 + 底部大块留白。从边缘洪水填充抠掉纸底，
/// 只保留描边闭合的角色，避免详情卡右侧出现一块染色矩形。
const int kOpenHandStudioCutoutTolerance = 42;
const int kOpenHandStudioCutoutFeather = 2;
const int kOpenHandStudioCutoutMinPaperLuminance = 180;
const double kOpenHandStudioCutoutMaxPaperSaturation = 0.35;
const double kOpenHandStudioCutoutMinKeepFraction = 0.03;
const double kOpenHandStudioCutoutMaxKeepFraction = 0.40;
const int kOpenHandStudioCutoutTrimPadding = 4;
const int kOpenHandStudioCutoutMaxEdge = 1024;
const int kOpenHandStudioCutoutCacheSize = 20;
const int kOpenHandStudioCutoutMaxInflight = 24;
const Duration kOpenHandStudioCutoutTimeout = Duration(seconds: 4);
const double kOpenHandStudioCutoutLightOpacity = 1;
const double kOpenHandStudioCutoutDarkOpacity = 0.92;
const double kOpenHandStudioCutoutFallbackLightOpacity = 0.42;
const double kOpenHandStudioCutoutFallbackDarkOpacity = 0.28;
const Alignment kOpenHandStudioCutoutAlignment = Alignment.centerRight;
const Alignment kOpenHandStudioCutoutFallbackAlignment = Alignment(0, -0.42);
const double kOpenHandStudioCutoutFadeEnd = 0.18;

const List<Color> _kPortraitFadeColors = <Color>[
  Color(0x00FFFFFF),
  Color(0xFFFFFFFF),
];
const List<double> _kPortraitFadeStops = <double>[
  0,
  kOpenHandStudioCutoutFadeEnd,
];

final class OpenHandStudioCutoutFrame {
  const OpenHandStudioCutoutFrame({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

class _CutoutHandle {
  _CutoutHandle({required this.image, required this.cutout});

  final ui.Image image;
  final bool cutout;

  _CutoutHandle clone() => _CutoutHandle(image: image.clone(), cutout: cutout);

  void dispose() => image.dispose();
}

/// 抠图算法 + 解码缓存。同一 URL 共用一次处理，避免切换角色时重复洪水填充。
final class OpenHandStudioCutout {
  OpenHandStudioCutout._();

  static final LinkedHashMap<String, _CutoutHandle> _cache =
      LinkedHashMap<String, _CutoutHandle>();
  static final Map<String, Future<_CutoutHandle?>> _inflight =
      <String, Future<_CutoutHandle?>>{};
  static final OpenHandAsyncSemaphore _gate = OpenHandAsyncSemaphore(
    2,
    maxAllowedPermits: 4,
    maxWaiters: kOpenHandStudioCutoutMaxInflight,
  );

  static String cacheKey(String url, int? cacheWidth) =>
      cacheWidth == null ? url : '$url@$cacheWidth';

  /// 从 RGBA 缓冲抠掉与边缘连通的浅色纸底，并裁到角色外接矩形。
  static OpenHandStudioCutoutFrame? processRgba({
    required Uint8List rgba,
    required int width,
    required int height,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        width > kOpenHandStudioCutoutMaxEdge ||
        height > kOpenHandStudioCutoutMaxEdge) {
      return null;
    }
    final pixelCount = width * height;
    if (rgba.length < pixelCount * 4) return null;

    final mask = Uint8List(pixelCount);
    final queue = Int32List(pixelCount);
    var head = 0;
    var tail = 0;
    const tol2 =
        kOpenHandStudioCutoutTolerance * kOpenHandStudioCutoutTolerance;

    void enqueue(int index) {
      if (mask[index] != 0) return;
      mask[index] = 1;
      queue[tail++] = index;
    }

    for (var i = 0; i < pixelCount; i++) {
      if (rgba[i * 4 + 3] == 0) mask[i] = 1;
    }

    void seed(int x, int y) {
      final index = y * width + x;
      if (mask[index] != 0) return;
      final offset = index * 4;
      if (!_looksLikePaper(rgba[offset], rgba[offset + 1], rgba[offset + 2])) {
        return;
      }
      enqueue(index);
    }

    for (var x = 0; x < width; x++) {
      seed(x, 0);
      seed(x, height - 1);
    }
    for (var y = 0; y < height; y++) {
      seed(0, y);
      seed(width - 1, y);
    }
    if (tail == 0) return null;

    void visit(int x, int y, int sourceOffset) {
      if (x < 0 || y < 0 || x >= width || y >= height) return;
      final index = y * width + x;
      if (mask[index] != 0) return;
      final offset = index * 4;
      if (_rgbDistance2(rgba, sourceOffset, offset) > tol2) return;
      enqueue(index);
    }

    while (head < tail) {
      final index = queue[head++];
      final x = index % width;
      final y = index ~/ width;
      final offset = index * 4;
      visit(x - 1, y, offset);
      visit(x + 1, y, offset);
      visit(x, y - 1, offset);
      visit(x, y + 1, offset);
    }

    var kept = 0;
    for (var i = 0; i < pixelCount; i++) {
      if (mask[i] == 0) kept++;
    }
    final fraction = kept / pixelCount;
    if (fraction < kOpenHandStudioCutoutMinKeepFraction ||
        fraction > kOpenHandStudioCutoutMaxKeepFraction) {
      return null;
    }

    const feather = kOpenHandStudioCutoutFeather;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        if (mask[index] == 0) continue;
        var nearest = feather + 1;
        for (var dy = -feather; dy <= feather; dy++) {
          for (var dx = -feather; dx <= feather; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
            if (mask[ny * width + nx] != 0) continue;
            final distance = math.max(dx.abs(), dy.abs());
            if (distance < nearest) nearest = distance;
          }
        }
        rgba[index * 4 + 3] = nearest > feather
            ? 0
            : (255 * (feather + 1 - nearest) / (feather + 1)).round();
      }
    }

    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (rgba[(y * width + x) * 4 + 3] <= 16) continue;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
    if (maxX < minX || maxY < minY) return null;

    minX = math.max(0, minX - kOpenHandStudioCutoutTrimPadding);
    minY = math.max(0, minY - kOpenHandStudioCutoutTrimPadding);
    maxX = math.min(width - 1, maxX + kOpenHandStudioCutoutTrimPadding);
    maxY = math.min(height - 1, maxY + kOpenHandStudioCutoutTrimPadding);
    final croppedWidth = maxX - minX + 1;
    final croppedHeight = maxY - minY + 1;
    final cropped = Uint8List(croppedWidth * croppedHeight * 4);
    for (var y = minY; y <= maxY; y++) {
      final source = (y * width + minX) * 4;
      final destination = (y - minY) * croppedWidth * 4;
      cropped.setRange(
        destination,
        destination + croppedWidth * 4,
        rgba,
        source,
      );
    }
    return OpenHandStudioCutoutFrame(
      bytes: cropped,
      width: croppedWidth,
      height: croppedHeight,
    );
  }

  static Future<_CutoutHandle?> _resolve(
    ImageProvider provider, {
    required String cacheKey,
  }) {
    final cached = _cloneCached(cacheKey);
    if (cached != null) return Future<_CutoutHandle?>.value(cached);
    final pending = _inflight[cacheKey];
    if (pending != null) {
      return pending.then(_cloneOwned);
    }
    if (_inflight.length >= kOpenHandStudioCutoutMaxInflight) {
      return Future<_CutoutHandle?>.value();
    }
    final future = _load(provider, cacheKey);
    _inflight[cacheKey] = future;
    return future
        .then(_cloneOwned)
        .whenComplete(() => _inflight.remove(cacheKey));
  }

  static Future<_CutoutHandle?> _load(
    ImageProvider provider,
    String cacheKey,
  ) async {
    final cached = _peek(cacheKey);
    if (cached != null) return cached;
    var acquired = false;
    try {
      acquired = await _gate.acquireWithin(kOpenHandStudioCutoutTimeout);
      if (!acquired) return _peek(cacheKey);
      final again = _peek(cacheKey);
      if (again != null) return again;
      final source = await _decodeFirstFrame(provider);
      if (source == null) return null;
      try {
        final pixels = await source.toByteData();
        if (pixels == null) {
          return _remember(
            cacheKey,
            _CutoutHandle(image: source.clone(), cutout: false),
          );
        }
        final frame = processRgba(
          rgba: Uint8List.fromList(
            pixels.buffer.asUint8List(
              pixels.offsetInBytes,
              pixels.lengthInBytes,
            ),
          ),
          width: source.width,
          height: source.height,
        );
        if (frame == null) {
          return _remember(
            cacheKey,
            _CutoutHandle(image: source.clone(), cutout: false),
          );
        }
        final cut = await _imageFromRgba(frame);
        return _remember(cacheKey, _CutoutHandle(image: cut, cutout: true));
      } finally {
        source.dispose();
      }
    } catch (_) {
      return _peek(cacheKey);
    } finally {
      if (acquired) _gate.release();
    }
  }

  static _CutoutHandle? _peek(String cacheKey) {
    final handle = _cache.remove(cacheKey);
    if (handle == null) return null;
    _cache[cacheKey] = handle;
    return handle;
  }

  static _CutoutHandle? _cloneCached(String cacheKey) =>
      _cloneOwned(_peek(cacheKey));

  static _CutoutHandle? _cloneOwned(_CutoutHandle? handle) {
    if (handle == null) return null;
    try {
      return handle.clone();
    } catch (_) {
      return null;
    }
  }

  static _CutoutHandle _remember(String cacheKey, _CutoutHandle handle) {
    final previous = _cache.remove(cacheKey);
    if (previous != null && !identical(previous.image, handle.image)) {
      previous.dispose();
    }
    _cache[cacheKey] = handle;
    while (_cache.length > kOpenHandStudioCutoutCacheSize) {
      _cache.remove(_cache.keys.first)?.dispose();
    }
    return handle;
  }

  static Future<ui.Image?> _decodeFirstFrame(ImageProvider provider) async {
    final completer = Completer<ui.Image?>();
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        stream.removeListener(listener);
        if (completer.isCompleted) {
          return;
        }
        completer.complete(info.image.clone());
      },
      onError: (Object _, StackTrace? _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    try {
      return await completer.future.timeout(kOpenHandStudioCutoutTimeout);
    } on TimeoutException {
      stream.removeListener(listener);
      return null;
    }
  }

  static Future<ui.Image> _imageFromRgba(OpenHandStudioCutoutFrame frame) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.bytes,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (completer.isCompleted) {
          image.dispose();
          return;
        }
        completer.complete(image);
      },
    );
    return completer.future;
  }

  static bool _looksLikePaper(int r, int g, int b) {
    final brightest = math.max(r, math.max(g, b));
    final darkest = math.min(r, math.min(g, b));
    final luminance = (r * 30 + g * 59 + b * 11) / 100;
    final saturation = brightest == 0 ? 0.0 : (brightest - darkest) / brightest;
    return luminance >= kOpenHandStudioCutoutMinPaperLuminance &&
        saturation <= kOpenHandStudioCutoutMaxPaperSaturation;
  }

  static int _rgbDistance2(Uint8List rgba, int left, int right) {
    final dr = rgba[left] - rgba[right];
    final dg = rgba[left + 1] - rgba[right + 1];
    final db = rgba[left + 2] - rgba[right + 2];
    return dr * dr + dg * dg + db * db;
  }
}

/// 详情卡右侧角色立绘：抠纸底后以 contain 融入着色面板，失败时回落原图 cover。
class OpenHandStudioCutoutPortrait extends StatefulWidget {
  const OpenHandStudioCutoutPortrait({
    super.key,
    required this.url,
    this.provider,
    this.cacheWidth,
    this.duration = kOpenHandMotion180,
  });

  final String url;
  final ImageProvider? provider;
  final int? cacheWidth;
  final Duration duration;

  @override
  State<OpenHandStudioCutoutPortrait> createState() =>
      _OpenHandStudioCutoutPortraitState();
}

class _OpenHandStudioCutoutPortraitState
    extends State<OpenHandStudioCutoutPortrait> {
  _CutoutHandle? _handle;
  int _generation = 0;

  ImageProvider get _provider {
    final injected = widget.provider;
    if (injected != null) return injected;
    final cacheWidth = widget.cacheWidth;
    final network = NetworkImage(widget.url);
    if (cacheWidth == null || cacheWidth <= 0) return network;
    return ResizeImage(network, width: cacheWidth);
  }

  String get _cacheKey =>
      OpenHandStudioCutout.cacheKey(widget.url, widget.cacheWidth);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant OpenHandStudioCutoutPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url &&
        oldWidget.cacheWidth == widget.cacheWidth &&
        oldWidget.provider == widget.provider) {
      return;
    }
    _handle?.dispose();
    _handle = null;
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _handle?.dispose();
    _handle = null;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _CutoutHandle? next;
    try {
      next = await OpenHandStudioCutout._resolve(
        _provider,
        cacheKey: _cacheKey,
      );
    } catch (_) {
      next = null;
    }
    if (!mounted || generation != _generation) {
      next?.dispose();
      return;
    }
    _handle?.dispose();
    setState(() => _handle = next);
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handle;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cutout = handle?.cutout ?? true;
    final opacity = handle == null
        ? 0.0
        : cutout
        ? (dark
              ? kOpenHandStudioCutoutDarkOpacity
              : kOpenHandStudioCutoutLightOpacity)
        : (dark
              ? kOpenHandStudioCutoutFallbackDarkOpacity
              : kOpenHandStudioCutoutFallbackLightOpacity);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: _kPortraitFadeColors,
        stops: _kPortraitFadeStops,
      ).createShader(bounds),
      child: AnimatedOpacity(
        opacity: opacity,
        duration: openHandMotionDuration(context, widget.duration),
        curve: kOpenHandSwitchInCurve,
        child: handle == null
            ? const SizedBox.expand()
            : RawImage(
                image: handle.image,
                fit: cutout ? BoxFit.contain : BoxFit.cover,
                alignment: cutout
                    ? kOpenHandStudioCutoutAlignment
                    : kOpenHandStudioCutoutFallbackAlignment,
              ),
      ),
    );
  }
}
