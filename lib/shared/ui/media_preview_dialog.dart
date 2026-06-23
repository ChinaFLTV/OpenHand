import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/support/silent_log.dart';
import '../util/byte_size_format.dart';
import '../util/localized_text.dart';
import 'animated_dialog.dart';
import 'interactive_image_preview.dart';
import 'motion_preference.dart';
import 'openhand_snack_bar.dart';

/// 通用图片 / 音频 / 视频预览弹窗。覆盖三种来源：
///   - `bytes`：内存 Uint8List（CDP 拉回的 base64 解码后的二进制）
///   - `network`：URL 直接交给 [Image.network] 或 webview 内嵌 `<audio>` / `<video>`
///   - `file`：本地文件路径
///
/// 与 home page 的 `_ImagePreviewDialog` 视觉一致：
///   - 弹窗外圈圆角 16，clipped Antialias
///   - 头部标题 + 关闭按钮 + 复制按钮
///   - 图片体积按真实宽高比动态贴合，四周 12px 统一留白；
///     不再因 `BoxFit.contain` 在固定容器内产生不均匀的上下 / 左右白边
///   - 音视频走 webview_flutter 沙箱，避免引入新依赖
enum MediaPreviewKind { image, audio, video }

class MediaPreviewDialog extends StatefulWidget {
  const MediaPreviewDialog._({
    this.bytes,
    this.networkUrl,
    this.filePath,
    this.mimeType,
    required this.kind,
    required this.title,
    this.onCopyUrl,
  });

  factory MediaPreviewDialog.bytes({
    required Uint8List bytes,
    required String title,
    String? sourceUrl,
    String? mimeType,
    MediaPreviewKind kind = MediaPreviewKind.image,
  }) => MediaPreviewDialog._(
    bytes: bytes,
    title: title,
    kind: kind,
    mimeType: mimeType,
    onCopyUrl: sourceUrl == null
        ? null
        : () => Clipboard.setData(ClipboardData(text: sourceUrl)),
  );

  factory MediaPreviewDialog.network({
    required String url,
    required String title,
    String? mimeType,
    MediaPreviewKind kind = MediaPreviewKind.image,
  }) => MediaPreviewDialog._(
    networkUrl: url,
    title: title,
    kind: kind,
    mimeType: mimeType,
    onCopyUrl: () => Clipboard.setData(ClipboardData(text: url)),
  );

  factory MediaPreviewDialog.file({
    required String filePath,
    required String title,
    String? mimeType,
    MediaPreviewKind kind = MediaPreviewKind.image,
  }) => MediaPreviewDialog._(
    filePath: filePath,
    title: title,
    kind: kind,
    mimeType: mimeType,
  );

  final Uint8List? bytes;
  final String? networkUrl;
  final String? filePath;
  final String? mimeType;
  final MediaPreviewKind kind;
  final String title;
  final VoidCallback? onCopyUrl;

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  /// 图片四周统一的内边距 (与会话气泡 `_ImagePreviewDialog` 12px 对齐)。
  static const double _kImagePadding = 12.0;
  static const double _kInsetPadding = 24.0;
  static const double _kHeaderEstimate = 70.0;
  static const double _kDividerH = 1.0;
  static const double _kMinDialogW = 324.0;
  static const double _kFallbackSide = 320.0;
  static const Duration _kClipboardTimeout = Duration(seconds: 15);
  static const Duration _kNetworkTimeout = Duration(seconds: 25);
  static const int _kClipboardMaxBytes = 64 * kBytesPerMiB;

  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  Size? _naturalSize;
  bool _copying = false;

  @override
  void initState() {
    super.initState();
    if (widget.kind == MediaPreviewKind.image) {
      _resolveImageDimensions();
    }
  }

  @override
  void dispose() {
    final stream = _imageStream;
    final listener = _imageStreamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    super.dispose();
  }

  /// 提前订阅 ImageProvider 流, 拿到图片自身的宽高用于尺寸计算。
  void _resolveImageDimensions() {
    ImageProvider? provider;
    if (widget.bytes != null) {
      provider = MemoryImage(widget.bytes!);
    } else if (widget.filePath != null) {
      provider = FileImage(File(widget.filePath!));
    } else if (widget.networkUrl != null) {
      provider = NetworkImage(widget.networkUrl!);
    }
    if (provider == null) return;
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w <= 0 || h <= 0) return;
        if (synchronousCall) {
          _naturalSize = Size(w, h);
          return;
        }
        if (!mounted) return;
        final prev = _naturalSize;
        if (prev != null && prev.width == w && prev.height == h) return;
        setState(() {
          _naturalSize = Size(w, h);
        });
      },
      onError: (Object _, StackTrace? _) {
        // 错误状态下保持 _naturalSize 为 null, 走占位尺寸分支。
      },
    );
    stream.addListener(listener);
    _imageStream = stream;
    _imageStreamListener = listener;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rawViewport = MediaQuery.sizeOf(context);
    final viewport = Size(
      rawViewport.width * kOpenHandDialogViewportFraction,
      rawViewport.height * kOpenHandDialogViewportFraction,
    );
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final motionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final isZh = openHandIsChineseLocale(context);

    final maxDialogW = math.max(
      _kMinDialogW,
      viewport.width - _kInsetPadding * 2,
    );
    final maxDialogH = math.max(200.0, viewport.height - _kInsetPadding * 2);

    final isImage = widget.kind == MediaPreviewKind.image;
    final padding = isImage ? _kImagePadding : 12.0;
    final maxBodyW = math.max(0.0, maxDialogW - padding * 2);
    final maxBodyH = math.max(
      0.0,
      maxDialogH - _kHeaderEstimate - _kDividerH - padding * 2,
    );

    double bodyW;
    double bodyH;
    if (isImage) {
      final natural = _naturalSize;
      if (natural != null && natural.width > 0 && natural.height > 0) {
        // 等比缩放至 maxBody 内接矩形, 与 BoxFit.contain 等价；尺寸直接落到外
        // 层 SizedBox 上, 因此四周不会再出现 letterbox 白边。
        final ratio = natural.width / natural.height;
        bodyW = maxBodyW;
        bodyH = bodyW / ratio;
        if (bodyH > maxBodyH) {
          bodyH = maxBodyH;
          bodyW = bodyH * ratio;
        }
      } else {
        final side = math.min(_kFallbackSide, math.min(maxBodyW, maxBodyH));
        bodyW = math.max(0.0, side);
        bodyH = math.max(0.0, side);
      }
    } else if (widget.kind == MediaPreviewKind.audio) {
      bodyW = maxBodyW.clamp(360.0, 980.0);
      bodyH = maxBodyH.clamp(360.0, 560.0);
    } else {
      bodyW = maxBodyW.clamp(320.0, 960.0);
      bodyH = maxBodyH.clamp(240.0, 640.0);
    }

    final dialogW = (bodyW + padding * 2).clamp(_kMinDialogW, maxDialogW);

    return Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.all(_kInsetPadding),
      constraints: BoxConstraints(
        minWidth: dialogW,
        maxWidth: dialogW,
        maxHeight: maxDialogH,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: disableAnim
            ? Duration.zero
            : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxDialogW,
            maxHeight: maxDialogH,
          ),
          child: SizedBox(
            width: dialogW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                  child: Row(
                    children: [
                      Icon(
                        switch (widget.kind) {
                          MediaPreviewKind.image => Icons.image_rounded,
                          MediaPreviewKind.audio => Icons.audiotrack_rounded,
                          MediaPreviewKind.video => Icons.movie_rounded,
                        },
                        size: 20,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: isZh ? '复制' : 'Copy',
                        onPressed: _copying
                            ? null
                            : () => _copyToClipboard(context),
                        icon: const Icon(Icons.content_copy_outlined),
                      ),
                      IconButton(
                        tooltip: isZh ? '关闭' : 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.all(padding),
                  child: SizedBox(
                    width: bodyW,
                    height: bodyH,
                    child: isImage
                        ? OpenHandInteractiveImagePreview(
                            child: KeyedSubtree(
                              key: ValueKey<String>(_imageSourceSignature),
                              child: _buildImage(context, Size(bodyW, bodyH)),
                            ),
                          )
                        : _MediaPlayerSurface(
                            title: widget.title,
                            bytes: widget.bytes,
                            networkUrl: widget.networkUrl,
                            filePath: widget.filePath,
                            mimeType: widget.mimeType,
                            kind: widget.kind,
                            motionDurationMs: motionSettings.disablesAnimation
                                ? 0
                                : motionSettings.duration.inMilliseconds,
                            motionCurveCss: _dialogCurveToCss(
                              motionSettings.curve,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _imageSourceSignature {
    final filePath = widget.filePath;
    if (filePath != null) return 'file:$filePath';
    final networkUrl = widget.networkUrl;
    if (networkUrl != null) return 'network:$networkUrl';
    final bytes = widget.bytes;
    if (bytes != null) {
      return 'bytes:${identityHashCode(bytes)}:${bytes.length}';
    }
    return 'empty:${widget.title}';
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      if (widget.kind == MediaPreviewKind.image) {
        final copiedImageData = await _copyImageSource();
        if (!context.mounted) return;
        _showCopySnack(
          context,
          zh: copiedImageData ? '已复制图片到剪贴板。' : '已复制图片文件或路径到剪贴板。',
          en: copiedImageData
              ? 'Copied image to clipboard.'
              : 'Copied image file or path to clipboard.',
        );
        return;
      }
      final filePath = widget.filePath;
      if (filePath != null) {
        final ok = await _copyFilePathToClipboard(filePath);
        if (!context.mounted) return;
        _showCopySnack(
          context,
          zh: ok ? '已复制媒体文件到剪贴板。' : '当前平台不支持直接复制媒体文件，已复制文件路径。',
          en: ok
              ? 'Copied media file to clipboard.'
              : 'Direct media file copy is unavailable on this platform. Copied the file path.',
        );
        return;
      }
      final url = widget.networkUrl;
      if (url != null) {
        widget.onCopyUrl?.call();
        await Clipboard.setData(
          ClipboardData(text: url),
        ).timeout(_kClipboardTimeout);
        if (!context.mounted) return;
        _showCopySnack(context, zh: '已复制媒体地址。', en: 'Copied media URL.');
        return;
      }
      final bytes = widget.bytes;
      if (bytes != null) {
        final tempPath = await _writeBytesToClipboardTempFile(bytes);
        final ok = await _copyFilePathToClipboard(tempPath);
        if (!context.mounted) return;
        _showCopySnack(
          context,
          zh: ok ? '已复制媒体文件到剪贴板。' : '当前平台不支持直接复制媒体文件，已复制临时文件路径。',
          en: ok
              ? 'Copied media file to clipboard.'
              : 'Direct media file copy is unavailable on this platform. Copied the temporary file path.',
        );
        return;
      }
      throw const FileSystemException('Media source is unavailable.');
    } catch (error) {
      final url = widget.networkUrl;
      if (url != null) {
        try {
          widget.onCopyUrl?.call();
          await Clipboard.setData(
            ClipboardData(text: url),
          ).timeout(_kClipboardTimeout);
          if (!context.mounted) return;
          _showCopySnack(
            context,
            zh: '无法复制媒体数据，已复制来源地址。',
            en: 'Unable to copy media data. Copied the source URL.',
          );
          return;
        } catch (_) {
          // Fall through to the error snackbar below.
        }
      }
      if (!context.mounted) return;
      _showCopySnack(
        context,
        zh: '复制失败：$error',
        en: 'Copy failed: $error',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<bool> _copyImageSource() async {
    final bytes = widget.bytes;
    if (bytes != null) {
      await Pasteboard.writeImage(bytes).timeout(_kClipboardTimeout);
      return true;
    }
    final filePath = widget.filePath;
    if (filePath != null) {
      final file = File(filePath);
      final stat = await file.stat().timeout(_kClipboardTimeout);
      if (stat.size > _kClipboardMaxBytes) {
        throw FileSystemException(
          'Image is too large for clipboard.',
          filePath,
        );
      }
      try {
        await Pasteboard.writeImage(
          await file.readAsBytes().timeout(_kClipboardTimeout),
        ).timeout(_kClipboardTimeout);
        return true;
      } catch (_) {
        await _copyFilePathToClipboard(filePath);
        return false;
      }
    }
    final url = widget.networkUrl;
    if (url != null) {
      final downloaded = await _downloadNetworkBytes(
        Uri.parse(url),
        expectedPrimaryType: 'image',
      );
      await Pasteboard.writeImage(downloaded).timeout(_kClipboardTimeout);
      return true;
    }
    throw const FileSystemException('Image source is unavailable.');
  }

  Future<bool> _copyFilePathToClipboard(String filePath) async {
    var ok = false;
    try {
      ok = await Pasteboard.writeFiles(<String>[
        filePath,
      ]).timeout(_kClipboardTimeout);
    } catch (_) {
      ok = false;
    } finally {
      await Clipboard.setData(
        ClipboardData(text: filePath),
      ).timeout(_kClipboardTimeout);
    }
    return ok;
  }

  Future<Uint8List> _downloadNetworkBytes(
    Uri uri, {
    String? expectedPrimaryType,
  }) async {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw FileSystemException(
        'Unsupported URI scheme: ${uri.scheme}',
        '$uri',
      );
    }
    final client = HttpClient()..connectionTimeout = _kNetworkTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_kNetworkTimeout);
      final response = await request.close().timeout(_kNetworkTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final contentType = response.headers.contentType;
      if (expectedPrimaryType != null &&
          contentType != null &&
          contentType.primaryType != expectedPrimaryType &&
          contentType.mimeType != 'application/octet-stream') {
        throw HttpException(
          'Unexpected content type: ${contentType.mimeType}',
          uri: uri,
        );
      }
      if (response.contentLength > _kClipboardMaxBytes) {
        throw HttpException('Response is too large for clipboard.', uri: uri);
      }
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response.timeout(_kNetworkTimeout)) {
        received += chunk.length;
        if (received > _kClipboardMaxBytes) {
          throw HttpException('Response is too large for clipboard.', uri: uri);
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _writeBytesToClipboardTempFile(Uint8List bytes) async {
    final dir = Directory.systemTemp;
    final ext = widget.kind == MediaPreviewKind.video ? 'mp4' : 'mp3';
    final file = File(
      '${dir.path}/oh-media-copy-${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
    await file.writeAsBytes(bytes, flush: true).timeout(_kClipboardTimeout);
    return file.path;
  }

  void _showCopySnack(
    BuildContext context, {
    required String zh,
    required String en,
    bool isError = false,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final isZh = openHandIsChineseLocale(context);
    OpenHandSnackBar.show(
      context,
      messenger,
      isError
          ? OpenHandSnackBar.error(context, isZh ? zh : en, maxLines: 2)
          : OpenHandSnackBar.success(context, isZh ? zh : en),
    );
  }

  Widget _buildImage(BuildContext context, Size displaySize) {
    if (widget.bytes != null) {
      return Image.memory(
        widget.bytes!,
        width: displaySize.width,
        height: displaySize.height,
        fit: BoxFit.contain,
        errorBuilder: (c, _, _) => _errorBox(c),
      );
    }
    if (widget.networkUrl != null) {
      return Image.network(
        widget.networkUrl!,
        width: displaySize.width,
        height: displaySize.height,
        fit: BoxFit.contain,
        errorBuilder: (c, _, _) => _errorBox(c),
      );
    }
    if (widget.filePath != null) {
      return Image.file(
        File(widget.filePath!),
        width: displaySize.width,
        height: displaySize.height,
        fit: BoxFit.contain,
        errorBuilder: (c, _, _) => _errorBox(c),
      );
    }
    return _errorBox(context);
  }

  Widget _errorBox(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Icon(Icons.broken_image_outlined, size: 48, color: cs.error),
        ),
      ),
    );
  }
}

/// 用 webview 内嵌一个最小化的 `<audio>` / `<video>` 播放器。
/// 内存 bytes 走 data URL（< 8MB）或写 temp 文件后转 file URL；
/// 网络 URL 直接挂到 `src`。播放控件使用自定义 overlay，进退场动效跟随
/// App 弹窗动效时长和曲线，避免浏览器原生 controls 生硬闪现。
class _MediaPlayerSurface extends StatefulWidget {
  const _MediaPlayerSurface({
    required this.title,
    required this.bytes,
    required this.networkUrl,
    required this.filePath,
    required this.mimeType,
    required this.kind,
    required this.motionDurationMs,
    required this.motionCurveCss,
  });

  final String title;
  final Uint8List? bytes;
  final String? networkUrl;
  final String? filePath;
  final String? mimeType;
  final MediaPreviewKind kind;
  final int motionDurationMs;
  final String motionCurveCss;

  @override
  State<_MediaPlayerSurface> createState() => _MediaPlayerSurfaceState();
}

class _MediaPlayerSurfaceState extends State<_MediaPlayerSurface> {
  static const int _kInlineDataUrlMaxBytes = 8 * kBytesPerMiB;
  static const int _kControlsAutoHideMs = 2600;
  static const String _kDefaultControlMotionCurveCss =
      'cubic-bezier(0.215, 0.61, 0.355, 1)';

  WebViewController? _controller;
  String? _tempHtmlPath;
  String? _tempMediaPath;
  String? _error;

  _AudioPreviewMeta get _audioMeta => _AudioPreviewMeta.fromText(
    title: widget.title,
    detail:
        widget.filePath ?? widget.networkUrl ?? widget.mimeType ?? 'OpenHand',
  );

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final mime =
          (widget.mimeType ??
                  (widget.kind == MediaPreviewKind.video
                      ? 'video/mp4'
                      : 'audio/mpeg'))
              .toLowerCase();
      String src;
      if (widget.networkUrl != null) {
        src = widget.networkUrl!;
      } else if (widget.filePath != null) {
        src = Uri.file(widget.filePath!).toString();
      } else if (widget.bytes != null) {
        // 大文件走 temp 文件，小文件直接 data:
        if (widget.bytes!.lengthInBytes <= _kInlineDataUrlMaxBytes) {
          src = 'data:$mime;base64,${base64Encode(widget.bytes!)}';
        } else {
          final dir = Directory.systemTemp;
          final ext = widget.kind == MediaPreviewKind.video ? 'mp4' : 'mp3';
          final f = File(
            '${dir.path}/oh-media-${DateTime.now().microsecondsSinceEpoch}.$ext',
          );
          await f.writeAsBytes(widget.bytes!, flush: true);
          _tempMediaPath = f.path;
          src = Uri.file(f.path).toString();
        }
      } else {
        setState(() => _error = 'no source');
        return;
      }
      final html = _buildPlayerHtml(src: src);
      final dir = Directory.systemTemp;
      final f = File(
        '${dir.path}/oh-media-host-${DateTime.now().microsecondsSinceEpoch}.html',
      );
      await f.writeAsString(html);
      _tempHtmlPath = f.path;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0F0F10))
        ..addJavaScriptChannel(
          'OpenHandMediaPreview',
          onMessageReceived: (_) => _requestDialogClose(),
        )
        ..loadFile(f.path);
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error, stack) {
      silentLog('media_preview', 'bootstrap webview host', error, stack);
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  String _htmlAttributeEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  String _htmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  void _requestDialogClose() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    unawaited(Navigator.of(context).maybePop());
  }

  String _buildPlayerHtml({required String src}) {
    final isAudio = widget.kind == MediaPreviewKind.audio;
    final durationMs = widget.motionDurationMs
        .clamp(0, DialogAnimationSettings.maxDurationMs)
        .toInt();
    final controlsClass = isAudio ? ' audio-mode' : '';
    final safeCurve = widget.motionCurveCss.trim().isEmpty
        ? _kDefaultControlMotionCurveCss
        : widget.motionCurveCss.trim();
    final escapedSrc = _htmlAttributeEscape(src);
    final meta = _audioMeta;
    final primaryHex = _hexColor(meta.primaryColor);
    final secondaryHex = _hexColor(meta.secondaryColor);
    final accentHex = _hexColor(meta.accentColor);
    final bgStartHex = _hexColor(
      _mixColors(meta.primaryColor, const Color(0xFF111111), 0.76),
    );
    final bgEndHex = _hexColor(
      _mixColors(meta.secondaryColor, const Color(0xFF1C1D18), 0.44),
    );
    final glowHex = _hexColor(
      _mixColors(meta.accentColor, Colors.transparent, 0.56),
    );
    final lyricItems = meta.lyricLines
        .map((line) => '<div class="lyric-line">${_htmlEscape(line)}</div>')
        .join();
    final lyricArray = _jsStringArrayLiteral(meta.lyricLines);
    final audioGraphEnabled =
        isAudio && widget.networkUrl == null && src.trim().isNotEmpty;
    final mediaTag = widget.kind == MediaPreviewKind.video
        ? '<video id="media" preload="metadata" autoplay playsinline src="$escapedSrc"></video>'
        : '<audio id="media" preload="metadata" autoplay playsinline crossorigin="anonymous" src="$escapedSrc"></audio>';
    final audioPlayer = isAudio
        ? '''
  <div class="audio-player" aria-label="${_htmlAttributeEscape(meta.title)}">
    <div class="audio-backdrop"></div>
    <div class="audio-volume-capsule">
      <div class="volume-group" id="volumeGroup">
        <button id="mute" class="control-button" type="button" aria-label="Mute"></button>
        <div class="volume-popover" id="volumePopover">
          <input id="volume" class="volume vertical" type="range" min="0" max="1" step="0.01" value="1" aria-label="Volume" aria-orientation="vertical">
        </div>
      </div>
    </div>
    <section class="album-column">
      <div class="album-cover" aria-hidden="true">
        <div class="album-disc"></div>
        <div class="album-glyph">${_htmlEscape(meta.coverGlyph)}</div>
      </div>
      <div class="track-meta">
        <div class="track-kicker">${_htmlEscape(meta.album)}</div>
        <div class="track-title">${_htmlEscape(meta.title)}</div>
        <div class="track-artist">${_htmlEscape(meta.artist)} · ${_htmlEscape(meta.detail)}</div>
      </div>
      <div class="audio-progress">
        <input id="progress" class="progress" type="range" min="0" max="1000" step="1" value="0" aria-label="Progress">
        <div class="time-row">
          <span id="current" class="time">00:00</span>
          <span id="duration" class="time">00:00</span>
        </div>
      </div>
      <div class="transport-row">
        <button id="rewind" class="control-button seek-button" type="button" aria-label="Back 15 seconds"></button>
        <button id="play" class="control-button play-main" type="button" aria-label="Play"></button>
        <button id="forward" class="control-button seek-button" type="button" aria-label="Forward 15 seconds"></button>
        <button id="playMode" class="control-button mode-button" type="button" aria-label="Playback mode"></button>
        <span id="modeLabel" class="mode-label">顺序</span>
      </div>
      <div class="effect-strip" id="effectStrip" aria-label="Sound effects">
        <button class="effect-chip is-active" type="button" data-effect="standard">标准</button>
        <button class="effect-chip" type="button" data-effect="spatial">3D</button>
        <button class="effect-chip" type="button" data-effect="vocal">人声</button>
        <button class="effect-chip" type="button" data-effect="warm">暖声</button>
      </div>
    </section>
    <section class="lyrics-column">
      <div class="lyrics-kicker">LYRICS</div>
      <div id="lyrics" class="lyrics-list">$lyricItems</div>
    </section>
  </div>
'''
        : '';
    final videoControls = isAudio
        ? ''
        : '''
  <div class="scrim"></div>
  <div class="control-bar" id="controls">
    <button id="rewind" class="control-button seek-button" type="button" aria-label="Back 15 seconds"></button>
    <button id="play" class="control-button" type="button" aria-label="Play"></button>
    <button id="forward" class="control-button seek-button" type="button" aria-label="Forward 15 seconds"></button>
    <span id="current" class="time">00:00</span>
    <input id="progress" class="progress" type="range" min="0" max="1000" step="1" value="0" aria-label="Progress">
    <span id="duration" class="time">00:00</span>
    <div class="volume-group" id="volumeGroup">
      <button id="mute" class="control-button" type="button" aria-label="Mute"></button>
      <div class="volume-popover" id="volumePopover">
        <input id="volume" class="volume vertical" type="range" min="0" max="1" step="0.01" value="1" aria-label="Volume" aria-orientation="vertical">
      </div>
    </div>
    <button id="playMode" class="control-button" type="button" aria-label="Stop after playback"></button>
    <button id="fullscreen" class="control-button" type="button" aria-label="Fullscreen"></button>
  </div>
''';
    return '''
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--oh-motion-duration:${durationMs}ms;--oh-motion-curve:$safeCurve;--oh-control-bg:rgba(18,18,20,.72);--oh-control-border:rgba(255,255,255,.16);--oh-control-text:#fff;--oh-track:rgba(255,255,255,.22);--oh-track-fill:#fff;--oh-audio-primary:$primaryHex;--oh-audio-secondary:$secondaryHex;--oh-audio-accent:$accentHex;--oh-audio-bg-start:$bgStartHex;--oh-audio-bg-end:$bgEndHex;--oh-audio-glow:$glowHex}
html,body{margin:0;padding:0;background:#0f0f10;height:100%;overflow:hidden;color:#fff;font:13px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
button,input{font:inherit}
.media-shell{position:relative;width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:#0f0f10;user-select:none;overflow:hidden;isolation:isolate}
.media-shell video{width:100%;height:100%;object-fit:contain;background:#000;border-radius:10px}
.media-shell audio{display:none}
.audio-player{display:none}
.audio-mode{display:block;background:linear-gradient(135deg,var(--oh-audio-bg-start),var(--oh-audio-bg-end))}
.audio-mode video{display:none}
.audio-mode .audio-player{position:absolute;inset:0;display:grid;grid-template-columns:minmax(250px,.92fr) minmax(280px,1.08fr);gap:40px;padding:32px 42px 28px;box-sizing:border-box;overflow:hidden}
.audio-backdrop{position:absolute;inset:-20%;z-index:-1;background:radial-gradient(circle at 24% 25%,var(--oh-audio-glow),transparent 26%),radial-gradient(circle at 82% 22%,rgba(255,255,255,.18),transparent 20%),radial-gradient(circle at 54% 82%,rgba(0,0,0,.24),transparent 32%);filter:blur(22px) saturate(1.14);transform:scale(1.04);animation:audioBackdropFloat 10s var(--oh-motion-curve) infinite alternate}
.audio-volume-capsule{position:absolute;right:18px;top:18px;z-index:6;display:flex;align-items:center;gap:10px;min-width:224px;height:46px;padding:0 14px;border:1px solid rgba(255,255,255,.32);border-radius:999px;background:rgba(255,255,255,.13);box-shadow:0 16px 34px rgba(0,0,0,.18);backdrop-filter:blur(22px) saturate(1.2);-webkit-backdrop-filter:blur(22px) saturate(1.2)}
.audio-volume-capsule:before{content:"";width:24px;height:24px;border-radius:50%;border:2px solid rgba(255,255,255,.84);box-sizing:border-box;box-shadow:inset 0 0 0 4px rgba(255,255,255,.20)}
.audio-volume-capsule .volume-group{flex:1;justify-content:flex-start;gap:10px}
.audio-volume-capsule .volume-popover{position:static;flex:1;width:auto;height:auto;border:0;background:transparent;box-shadow:none;backdrop-filter:none;-webkit-backdrop-filter:none;transform:none;opacity:1;pointer-events:auto;filter:none}
.audio-volume-capsule .volume.vertical{position:static;width:100%;transform:none}
.album-column{min-width:0;display:flex;flex-direction:column;align-items:stretch;justify-content:flex-start;padding-top:56px}
.album-cover{position:relative;width:min(100%,320px);aspect-ratio:1;margin:0 auto 20px;border-radius:22px;overflow:hidden;background:linear-gradient(135deg,var(--oh-audio-accent),var(--oh-audio-secondary) 48%,var(--oh-audio-primary));box-shadow:0 34px 64px rgba(0,0,0,.30),0 0 0 1px rgba(255,255,255,.20);transform-origin:center;animation:albumFloat 5.8s var(--oh-motion-curve) infinite alternate}
.album-cover:before{content:"";position:absolute;inset:13%;border-radius:50%;background:radial-gradient(circle at 34% 35%,rgba(255,255,255,.44),rgba(255,255,255,.10) 28%,rgba(0,0,0,.12) 29%,transparent 58%);box-shadow:0 0 0 1px rgba(255,255,255,.18)}
.album-cover:after{content:"";position:absolute;inset:0;background:linear-gradient(120deg,rgba(255,255,255,.18),transparent 36%,rgba(0,0,0,.18));mix-blend-mode:screen}
.album-disc{position:absolute;right:-16%;bottom:-18%;width:70%;height:70%;border-radius:50%;background:repeating-radial-gradient(circle,rgba(255,255,255,.18) 0 2px,rgba(255,255,255,.04) 3px 7px);opacity:.42}
.album-glyph{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;padding:20px;box-sizing:border-box;color:rgba(255,255,255,.94);font-size:clamp(58px,10vw,94px);font-weight:900;line-height:1;text-shadow:0 12px 34px rgba(0,0,0,.26)}
.track-meta{min-width:0;text-align:left;color:#fff;text-shadow:0 8px 30px rgba(0,0,0,.22)}
.track-kicker{max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:rgba(255,255,255,.58);font-size:12px;font-weight:800;letter-spacing:.06em;text-transform:uppercase}
.track-title{margin-top:4px;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:clamp(22px,3.1vw,31px);font-weight:900;letter-spacing:0}
.track-artist{margin-top:4px;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:rgba(255,255,255,.70);font-size:14px;font-weight:700}
.audio-progress{margin-top:22px}
.time-row{display:flex;align-items:center;justify-content:space-between;margin-top:6px;color:rgba(255,255,255,.70)}
.transport-row{display:flex;align-items:center;justify-content:center;gap:18px;margin-top:14px}
.play-main{width:58px!important;height:58px!important;min-width:58px!important;background:rgba(255,255,255,.22)!important;box-shadow:0 14px 30px rgba(0,0,0,.20)}
.play-main svg{width:32px!important;height:32px!important}
.mode-button{background:rgba(255,255,255,.14)}
.mode-label{min-width:40px;color:rgba(255,255,255,.68);font-weight:800;font-size:12px;white-space:nowrap}
.effect-strip{display:flex;align-items:center;gap:8px;margin-top:14px;min-width:0;overflow:hidden}
.effect-chip{height:30px;padding:0 12px;border:1px solid rgba(255,255,255,.18);border-radius:999px;background:rgba(255,255,255,.09);color:rgba(255,255,255,.76);font-size:12px;font-weight:800;white-space:nowrap;cursor:pointer;transition:background-color 160ms ease-out,color 160ms ease-out,transform 160ms var(--oh-motion-curve),border-color 160ms ease-out}
.effect-chip:hover,.effect-chip:focus-visible{outline:none;transform:translateY(-1px) scale(1.03);background:rgba(255,255,255,.16)}
.effect-chip.is-active{color:#1f241c;background:rgba(255,255,255,.86);border-color:rgba(255,255,255,.92)}
.lyrics-column{min-width:0;display:flex;flex-direction:column;justify-content:center;padding:70px 12px 34px}
.lyrics-kicker{margin-bottom:22px;color:rgba(255,255,255,.44);font-size:12px;font-weight:900;letter-spacing:.12em}
.lyrics-list{position:relative;max-height:360px;overflow:hidden;padding:28px 0;mask-image:linear-gradient(to bottom,transparent,#000 18%,#000 82%,transparent);-webkit-mask-image:linear-gradient(to bottom,transparent,#000 18%,#000 82%,transparent)}
.lyric-line{padding:14px 0;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:rgba(255,255,255,.34);font-size:clamp(22px,3vw,36px);font-weight:900;letter-spacing:0;filter:blur(2px);transform:translateX(0) scale(.98);transition:color var(--oh-motion-duration) var(--oh-motion-curve),filter var(--oh-motion-duration) var(--oh-motion-curve),transform var(--oh-motion-duration) var(--oh-motion-curve)}
.lyric-line.is-active{color:rgba(255,255,255,.96);filter:blur(0);transform:translateX(6px) scale(1)}
.scrim{position:absolute;inset:auto 0 0;height:38%;background:linear-gradient(to top,rgba(0,0,0,.48),transparent);opacity:1;transition:opacity var(--oh-motion-duration) var(--oh-motion-curve);pointer-events:none}
.media-shell:not(.controls-visible) .scrim{opacity:0}
.control-bar{position:absolute;left:50%;bottom:12px;z-index:5;display:flex;align-items:center;gap:10px;width:calc(100% - 40px);max-width:820px;min-height:48px;padding:8px 14px;box-sizing:border-box;border:1px solid var(--oh-control-border);border-radius:999px;background:var(--oh-control-bg);color:var(--oh-control-text);box-shadow:0 18px 42px rgba(0,0,0,.36);backdrop-filter:blur(22px) saturate(1.24);-webkit-backdrop-filter:blur(22px) saturate(1.24);transform-origin:bottom center;transform:translateX(-50%) translateY(0) scale(1);opacity:1;filter:blur(0);transition:opacity var(--oh-motion-duration) var(--oh-motion-curve),transform var(--oh-motion-duration) var(--oh-motion-curve),filter var(--oh-motion-duration) var(--oh-motion-curve)}
.media-shell:not(.controls-visible) .control-bar{opacity:0;pointer-events:none;transform:translateX(-50%) translateY(24px) scale(.94);filter:blur(4px)}
.control-button{width:28px;height:28px;border:0;border-radius:999px;display:inline-flex;align-items:center;justify-content:center;background:transparent;color:#fff;cursor:pointer;transition:transform 160ms var(--oh-motion-curve),background-color 160ms ease-out,opacity 160ms ease-out}
.control-button:hover,.control-button:focus-visible{background:rgba(255,255,255,.14);transform:translateY(-1px) scale(1.06);outline:none}
.control-button.is-active{background:rgba(255,255,255,.20)}
.control-button:active{transform:scale(.92)}
.control-button svg{width:18px;height:18px;display:block;fill:currentColor}
.seek-button svg{width:21px;height:21px}
.time{min-width:48px;text-align:center;font-weight:700;font-variant-numeric:tabular-nums;color:rgba(255,255,255,.92);white-space:nowrap}
.progress{flex:1 1 180px;min-width:96px}
.volume-group{position:relative;display:inline-flex;align-items:center;justify-content:center}
.volume-popover{position:absolute;left:50%;bottom:38px;width:46px;height:136px;display:flex;align-items:center;justify-content:center;border:1px solid var(--oh-control-border);border-radius:999px;background:var(--oh-control-bg);box-shadow:0 18px 42px rgba(0,0,0,.34);backdrop-filter:blur(22px) saturate(1.24);-webkit-backdrop-filter:blur(22px) saturate(1.24);transform-origin:bottom center;transform:translateX(-50%) translateY(10px) scale(.88);opacity:0;pointer-events:none;filter:blur(3px);transition:opacity var(--oh-motion-duration) var(--oh-motion-curve),transform var(--oh-motion-duration) var(--oh-motion-curve),filter var(--oh-motion-duration) var(--oh-motion-curve)}
.volume-open .volume-popover,.volume-group:focus-within .volume-popover{opacity:1;pointer-events:auto;transform:translateX(-50%) translateY(0) scale(1);filter:blur(0)}
.volume{width:118px}
.volume.vertical{position:absolute;left:50%;top:50%;width:112px;transform:translate(-50%,-50%) rotate(-90deg);transform-origin:center}
input[type=range]{height:22px;margin:0;accent-color:#fff;cursor:pointer}
input[type=range]::-webkit-slider-runnable-track{height:7px;border-radius:999px;background:linear-gradient(to right,var(--oh-track-fill) 0%,var(--oh-track-fill) var(--value,0%),var(--oh-track) var(--value,0%),var(--oh-track) 100%)}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:18px;height:18px;margin-top:-5.5px;border-radius:50%;background:#fff;box-shadow:0 2px 10px rgba(0,0,0,.35);transition:transform 160ms var(--oh-motion-curve)}
input[type=range]:hover::-webkit-slider-thumb,input[type=range]:focus-visible::-webkit-slider-thumb{transform:scale(1.12)}
.audio-mode input[type=range]::-webkit-slider-runnable-track{height:8px;background:linear-gradient(to right,rgba(255,255,255,.90) 0%,rgba(255,255,255,.90) var(--value,0%),rgba(255,255,255,.24) var(--value,0%),rgba(255,255,255,.24) 100%)}
.audio-mode input[type=range]::-webkit-slider-thumb{width:20px;height:20px;margin-top:-6px}
.audio-mode .control-button:hover,.audio-mode .control-button:focus-visible{background:rgba(255,255,255,.18)}
@keyframes albumFloat{from{transform:translateY(0) scale(1)}to{transform:translateY(-7px) scale(1.015)}}
@keyframes audioBackdropFloat{from{transform:scale(1.04) translate3d(0,0,0)}to{transform:scale(1.08) translate3d(-1.4%,1.2%,0)}}
.no-motion *{transition-duration:0ms!important;animation:none!important}
@media (max-width:820px){.audio-mode .audio-player{grid-template-columns:1fr;gap:18px;padding:24px 26px 22px}.audio-volume-capsule{right:14px;top:14px;min-width:184px}.album-column{padding-top:44px}.album-cover{width:min(58vw,210px);margin-bottom:14px}.lyrics-column{padding:0 2px 0}.lyrics-list{max-height:150px;padding:10px 0}.lyric-line{padding:8px 0;font-size:22px}.effect-strip{overflow-x:auto;padding-bottom:2px}}
@media (max-width:720px){.control-bar{gap:6px;padding:7px 10px;width:calc(100% - 28px)}.progress{min-width:72px}.time{min-width:42px}.volume-popover{height:116px}.volume.vertical{width:94px}.audio-volume-capsule .volume-popover{height:auto}.audio-volume-capsule .volume.vertical{width:100%}}
@media (max-width:420px){.seek-button{display:none}.control-bar{width:calc(100% - 20px)}.time{min-width:40px}.progress{min-width:64px}.volume-popover{height:104px}.volume.vertical{width:84px}.audio-mode .audio-player{padding:20px 18px}.audio-volume-capsule{left:18px;right:18px;min-width:0}.track-title{font-size:22px}.effect-chip{padding:0 10px}.audio-volume-capsule .volume-popover{height:auto}.audio-volume-capsule .volume.vertical{width:100%}}
</style></head><body>
<div id="shell" class="media-shell controls-visible$controlsClass${durationMs == 0 ? ' no-motion' : ''}" tabindex="0">
  $mediaTag
  $audioPlayer
  $videoControls
</div>
<script>
(() => {
  const AUTO_HIDE_MS = $_kControlsAutoHideMs;
  const IS_AUDIO = ${isAudio ? 'true' : 'false'};
  const AUDIO_GRAPH_ENABLED = ${audioGraphEnabled ? 'true' : 'false'};
  const lyricLines = $lyricArray;
  const shell = document.getElementById('shell');
  const media = document.getElementById('media');
  const play = document.getElementById('play');
  const rewind = document.getElementById('rewind');
  const forward = document.getElementById('forward');
  const progress = document.getElementById('progress');
  const current = document.getElementById('current');
  const duration = document.getElementById('duration');
  const volume = document.getElementById('volume');
  const mute = document.getElementById('mute');
  const volumeGroup = document.getElementById('volumeGroup');
  const playMode = document.getElementById('playMode');
  const modeLabel = document.getElementById('modeLabel');
  const fullscreen = document.getElementById('fullscreen');
  const lyrics = Array.from(document.querySelectorAll('.lyric-line'));
  const effectButtons = Array.from(document.querySelectorAll('[data-effect]'));
  if (!media || !play || !rewind || !forward || !progress || !current || !duration || !volume || !mute || !volumeGroup || !playMode) {
    requestClose();
    return;
  }
  let hideTimer = 0;
  let dragging = false;
  let volumeActive = false;
  let playbackMode = IS_AUDIO ? 'sequence' : 'stop';
  let activeLyricIndex = -1;
  let activeEffect = 'standard';
  let audioCtx = null;
  let sourceNode = null;
  let effectNodes = [];
  let spatialFrame = 0;

  const icon = {
    play: '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>',
    pause: '<svg viewBox="0 0 24 24"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>',
    mute: '<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4z"/><path d="M18 9l4 4m0-4-4 4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    volume: '<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4z"/><path d="M16 8.5a5 5 0 010 7M18.5 6a8 8 0 010 12" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    rewind: '<svg viewBox="0 0 24 24"><path d="M11 7l-6 5 6 5V7zm8 0l-6 5 6 5V7z"/><text x="12" y="21" text-anchor="middle" font-size="7" fill="currentColor">15</text></svg>',
    forward: '<svg viewBox="0 0 24 24"><path d="M13 7l6 5-6 5V7zM5 7l6 5-6 5V7z"/><text x="12" y="21" text-anchor="middle" font-size="7" fill="currentColor">15</text></svg>',
    loop: '<svg viewBox="0 0 24 24"><path d="M17 2l4 4-4 4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 11V9a3 3 0 013-3h15" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M7 22l-4-4 4-4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M21 13v2a3 3 0 01-3 3H3" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    stopAfter: '<svg viewBox="0 0 24 24"><rect x="7" y="7" width="10" height="10" rx="2"/><path d="M4 12h1.5M18.5 12H20" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    sequence: '<svg viewBox="0 0 24 24"><path d="M5 7h9M5 12h13M5 17h9" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round"/><path d="M16 6l3 3-3 3" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    repeatOne: '<svg viewBox="0 0 24 24"><path d="M17 2l4 4-4 4M3 11V9a3 3 0 013-3h15M7 22l-4-4 4-4M21 13v2a3 3 0 01-3 3H3" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><text x="12" y="15" text-anchor="middle" font-size="8" font-weight="800" fill="currentColor">1</text></svg>',
    shuffle: '<svg viewBox="0 0 24 24"><path d="M16 3h5v5M4 7h3c5 0 6 10 11 10h3M4 17h3c2.2 0 3.5-1.7 4.7-3.8M15.8 6.5C17 5.5 18.3 5 21 5M16 21h5v-5" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    fullscreen: '<svg viewBox="0 0 24 24"><path d="M5 9V5h4M15 5h4v4M19 15v4h-4M9 19H5v-4" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  };

  rewind.innerHTML = icon.rewind;
  forward.innerHTML = icon.forward;
  if (fullscreen) fullscreen.innerHTML = icon.fullscreen;

  function requestClose() {
    try { window.OpenHandMediaPreview?.postMessage('close'); } catch (_) {}
  }

  function formatTime(value) {
    if (!Number.isFinite(value) || value < 0) return '00:00';
    const total = Math.floor(value);
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const seconds = total % 60;
    const pad = (n) => String(n).padStart(2, '0');
    return hours > 0
      ? hours + ':' + pad(minutes) + ':' + pad(seconds)
      : pad(minutes) + ':' + pad(seconds);
  }

  function setRangeFill(input, ratio) {
    const value = Math.max(0, Math.min(100, ratio * 100));
    input.style.setProperty('--value', value + '%');
  }

  function updatePlayState() {
    play.innerHTML = media.paused ? icon.play : icon.pause;
    play.setAttribute('aria-label', media.paused ? 'Play' : 'Pause');
    if (media.paused || media.ended) {
      showControls(true);
    } else {
      scheduleHide();
    }
  }

  function updateTime() {
    const dur = Number.isFinite(media.duration) ? media.duration : 0;
    const cur = Number.isFinite(media.currentTime) ? media.currentTime : 0;
    current.textContent = formatTime(cur);
    duration.textContent = formatTime(dur);
    const ratio = dur > 0 ? cur / dur : 0;
    progress.value = String(Math.round(ratio * 1000));
    setRangeFill(progress, ratio);
    updateLyrics(cur, dur);
  }

  function updateVolume() {
    const muted = media.muted || media.volume <= 0;
    mute.innerHTML = muted ? icon.mute : icon.volume;
    mute.setAttribute('aria-label', muted ? 'Unmute' : 'Mute');
    volume.value = String(media.muted ? 0 : media.volume);
    setRangeFill(volume, media.muted ? 0 : media.volume);
  }

  function updatePlayMode() {
    if (IS_AUDIO) {
      const labels = { sequence: '顺序', repeat: '单曲', shuffle: '随机' };
      const aria = { sequence: 'Sequential playback', repeat: 'Repeat one', shuffle: 'Shuffle playback' };
      media.loop = playbackMode === 'repeat';
      playMode.innerHTML = playbackMode === 'repeat'
        ? icon.repeatOne
        : playbackMode === 'shuffle'
          ? icon.shuffle
          : icon.sequence;
      playMode.classList.toggle('is-active', playbackMode !== 'sequence');
      playMode.setAttribute('aria-label', aria[playbackMode] || aria.sequence);
      playMode.setAttribute('title', aria[playbackMode] || aria.sequence);
      if (modeLabel) modeLabel.textContent = labels[playbackMode] || labels.sequence;
      return;
    }
    const looping = playbackMode === 'loop';
    media.loop = looping;
    playMode.innerHTML = looping ? icon.loop : icon.stopAfter;
    playMode.classList.toggle('is-active', looping);
    playMode.setAttribute('aria-label', looping ? 'Loop playback' : 'Stop after playback');
    playMode.setAttribute('title', looping ? 'Loop playback' : 'Stop after playback');
  }

  function clearHideTimer() {
    if (hideTimer) window.clearTimeout(hideTimer);
    hideTimer = 0;
  }

  function showControls(sticky = false) {
    shell.classList.add('controls-visible');
    if (sticky) {
      clearHideTimer();
      return;
    }
    scheduleHide();
  }

  function scheduleHide() {
    clearHideTimer();
    if (IS_AUDIO) return;
    if (media.paused || dragging || volumeActive) return;
    hideTimer = window.setTimeout(() => {
      if (!media.paused && !dragging && !volumeActive) {
        shell.classList.remove('controls-visible');
        shell.classList.remove('volume-open');
      }
    }, AUTO_HIDE_MS);
  }

  function beginProgressDrag(event) {
    dragging = true;
    progress.setPointerCapture?.(event.pointerId);
    showControls(true);
  }

  function endProgressDrag(event) {
    if (!dragging) return;
    dragging = false;
    progress.releasePointerCapture?.(event.pointerId);
    scheduleHide();
  }

  function setVolumeActive(active) {
    volumeActive = active;
    shell.classList.toggle('volume-open', active);
    if (active) {
      showControls(true);
    } else {
      scheduleHide();
    }
  }

  function updateLyrics(cur, dur) {
    if (!lyrics.length) return;
    const fallbackSpan = Math.max(1, lyrics.length * 6);
    const ratio = dur > 0 ? cur / dur : (cur % fallbackSpan) / fallbackSpan;
    const nextIndex = Math.max(0, Math.min(lyrics.length - 1, Math.floor(ratio * lyrics.length)));
    if (nextIndex === activeLyricIndex) return;
    activeLyricIndex = nextIndex;
    lyrics.forEach((line, index) => line.classList.toggle('is-active', index === nextIndex));
    const active = lyrics[nextIndex];
    if (active) {
      active.scrollIntoView({
        block: 'center',
        inline: 'nearest',
        behavior: shell.classList.contains('no-motion') ? 'auto' : 'smooth'
      });
    }
  }

  function stopSpatialMotion() {
    if (spatialFrame) window.cancelAnimationFrame(spatialFrame);
    spatialFrame = 0;
  }

  function clearEffectGraph() {
    stopSpatialMotion();
    effectNodes.forEach((node) => {
      try { node.disconnect(); } catch (_) {}
    });
    effectNodes = [];
  }

  function ensureAudioGraph() {
    if (!IS_AUDIO || !AUDIO_GRAPH_ENABLED) return false;
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return false;
    try {
      if (!audioCtx) audioCtx = new Ctx();
      if (!sourceNode) sourceNode = audioCtx.createMediaElementSource(media);
      if (audioCtx.state === 'suspended') audioCtx.resume().catch(() => {});
      return true;
    } catch (_) {
      return false;
    }
  }

  function connectEffectNodes(nodes, animatePanner) {
    if (!sourceNode || !audioCtx) return;
    try { sourceNode.disconnect(); } catch (_) {}
    let tail = sourceNode;
    nodes.forEach((node) => {
      tail.connect(node);
      tail = node;
    });
    tail.connect(audioCtx.destination);
    if (animatePanner && nodes.length) {
      const panner = nodes[nodes.length - 1];
      const tick = () => {
        if (activeEffect !== 'spatial' || !panner) return;
        try { panner.pan.value = Math.sin((media.currentTime || 0) * 1.6) * 0.34; } catch (_) {}
        spatialFrame = window.requestAnimationFrame(tick);
      };
      tick();
    }
  }

  function applyEffect(mode) {
    activeEffect = mode || 'standard';
    effectButtons.forEach((button) => {
      button.classList.toggle('is-active', button.dataset.effect === activeEffect);
    });
    clearEffectGraph();
    if (!ensureAudioGraph()) return;
    try {
      const nodes = [];
      let animatePanner = false;
      if (activeEffect === 'spatial' && audioCtx.createStereoPanner) {
        const panner = audioCtx.createStereoPanner();
        panner.pan.value = 0.16;
        nodes.push(panner);
        animatePanner = true;
      } else if (activeEffect === 'vocal') {
        const highpass = audioCtx.createBiquadFilter();
        highpass.type = 'highpass';
        highpass.frequency.value = 90;
        const presence = audioCtx.createBiquadFilter();
        presence.type = 'peaking';
        presence.frequency.value = 2800;
        presence.Q.value = 0.9;
        presence.gain.value = 4.2;
        nodes.push(highpass, presence);
      } else if (activeEffect === 'warm') {
        const lowShelf = audioCtx.createBiquadFilter();
        lowShelf.type = 'lowshelf';
        lowShelf.frequency.value = 180;
        lowShelf.gain.value = 4.5;
        const softHigh = audioCtx.createBiquadFilter();
        softHigh.type = 'highshelf';
        softHigh.frequency.value = 5200;
        softHigh.gain.value = -1.8;
        nodes.push(lowShelf, softHigh);
      }
      effectNodes = nodes;
      connectEffectNodes(nodes, animatePanner);
    } catch (_) {
      clearEffectGraph();
    }
  }

  function seekBy(delta) {
    const dur = Number.isFinite(media.duration) ? media.duration : 0;
    const next = Math.max(0, Math.min(dur || Number.MAX_SAFE_INTEGER, media.currentTime + delta));
    media.currentTime = next;
    updateTime();
    showControls();
  }

  play.addEventListener('click', () => {
    if (media.paused) {
      if (IS_AUDIO) {
        ensureAudioGraph();
        if (activeEffect !== 'standard') applyEffect(activeEffect);
      }
      media.play().catch(() => showControls(true));
    } else {
      media.pause();
    }
    showControls(true);
  });
  rewind.addEventListener('click', () => seekBy(-15));
  forward.addEventListener('click', () => seekBy(15));
  progress.addEventListener('pointerdown', beginProgressDrag);
  progress.addEventListener('pointerup', endProgressDrag);
  progress.addEventListener('pointercancel', endProgressDrag);
  progress.addEventListener('input', () => {
    const dur = Number.isFinite(media.duration) ? media.duration : 0;
    if (dur > 0) media.currentTime = (Number(progress.value) / 1000) * dur;
    updateTime();
    showControls(true);
  });
  volumeGroup.addEventListener('pointerenter', () => setVolumeActive(true));
  volumeGroup.addEventListener('pointerleave', () => setVolumeActive(false));
  volumeGroup.addEventListener('pointerdown', () => setVolumeActive(true));
  volumeGroup.addEventListener('pointerup', () => setVolumeActive(false));
  volumeGroup.addEventListener('pointercancel', () => setVolumeActive(false));
  volumeGroup.addEventListener('focusin', () => setVolumeActive(true));
  volumeGroup.addEventListener('focusout', (event) => {
    if (!event.relatedTarget || !volumeGroup.contains(event.relatedTarget)) {
      setVolumeActive(false);
    }
  });
  volume.addEventListener('input', () => {
    const next = Math.max(0, Math.min(1, Number(volume.value)));
    media.volume = Number.isFinite(next) ? next : 1;
    media.muted = media.volume <= 0;
    updateVolume();
    shell.classList.add('volume-open');
    showControls(volumeActive);
  });
  mute.addEventListener('click', () => {
    media.muted = !media.muted;
    if (!media.muted && media.volume <= 0) media.volume = 0.6;
    updateVolume();
    shell.classList.add('volume-open');
    setVolumeActive(true);
  });
  playMode.addEventListener('click', () => {
    if (IS_AUDIO) {
      playbackMode = playbackMode === 'sequence'
        ? 'repeat'
        : playbackMode === 'repeat'
          ? 'shuffle'
          : 'sequence';
    } else {
      playbackMode = playbackMode === 'loop' ? 'stop' : 'loop';
    }
    updatePlayMode();
    showControls(true);
  });
  effectButtons.forEach((button) => {
    button.addEventListener('click', () => {
      applyEffect(button.dataset.effect || 'standard');
      showControls(true);
    });
  });
  if (fullscreen) {
    fullscreen.addEventListener('click', () => {
      const target = shell;
      if (document.fullscreenElement) {
        document.exitFullscreen?.();
      } else {
        target.requestFullscreen?.().catch(() => {});
      }
      showControls();
    });
  }
  shell.addEventListener('pointermove', () => showControls());
  shell.addEventListener('pointerdown', () => showControls());
  shell.addEventListener('pointerleave', () => scheduleHide());
  shell.addEventListener('focusin', (event) => showControls(event.target !== shell));
  shell.addEventListener('focusout', () => scheduleHide());
  shell.addEventListener('keydown', (event) => {
    if (event.defaultPrevented) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      requestClose();
    } else if (event.key === ' ' || event.key === 'Enter') {
      event.preventDefault();
      play.click();
    } else if (event.key === 'ArrowLeft') {
      event.preventDefault();
      seekBy(-5);
    } else if (event.key === 'ArrowRight') {
      event.preventDefault();
      seekBy(5);
    } else if (event.key.toLowerCase() === 'm') {
      event.preventDefault();
      mute.click();
    }
  });
  document.addEventListener('keydown', (event) => {
    if (event.defaultPrevented || event.key !== 'Escape') return;
    event.preventDefault();
    requestClose();
  }, true);
  media.addEventListener('loadedmetadata', updateTime);
  media.addEventListener('durationchange', updateTime);
  media.addEventListener('timeupdate', updateTime);
  media.addEventListener('play', updatePlayState);
  media.addEventListener('pause', updatePlayState);
  media.addEventListener('ended', () => {
    if (IS_AUDIO && playbackMode === 'shuffle') {
      const dur = Number.isFinite(media.duration) ? media.duration : 0;
      try { media.currentTime = dur > 3 ? Math.random() * Math.max(1, dur - 1) : 0; } catch (_) {}
      media.play().catch(() => showControls(true));
    }
    updatePlayState();
    showControls(true);
  });
  media.addEventListener('volumechange', updateVolume);
  window.addEventListener('beforeunload', () => {
    clearHideTimer();
    clearEffectGraph();
  });
  updatePlayMode();
  updatePlayState();
  updateTime();
  updateVolume();
  applyEffect('standard');
  media.play?.().catch(() => updatePlayState());
})();
</script>
</body></html>
''';
  }

  @override
  void dispose() {
    final p = _tempHtmlPath;
    if (p != null) {
      unawaited(File(p).delete().catchError((_) => File(p)));
    }
    final m = _tempMediaPath;
    if (m != null) {
      unawaited(File(m).delete().catchError((_) => File(m)));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_error != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.error),
            ),
          ),
        ),
      );
    }
    if (_controller == null) {
      return Center(child: CircularProgressIndicator(color: cs.primary));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: WebViewWidget(controller: _controller!),
    );
  }
}

class _AudioPreviewMeta {
  const _AudioPreviewMeta({
    required this.title,
    required this.artist,
    required this.album,
    required this.detail,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.coverGlyph,
    required this.lyricLines,
  });

  factory _AudioPreviewMeta.fromText({
    required String title,
    required String detail,
  }) {
    final cleanTitle = _normalizeAudioPreviewText(title, fallback: 'Audio');
    final cleanDetail = _normalizeAudioPreviewText(
      detail,
      fallback: 'OpenHand',
    );
    final seed = '$cleanTitle|$cleanDetail'.hashCode & 0x7fffffff;
    final palette =
        _kAudioPreviewPalettes[seed % _kAudioPreviewPalettes.length];
    return _AudioPreviewMeta(
      title: cleanTitle,
      artist: _deriveAudioPreviewArtist(cleanDetail),
      album: _deriveAudioPreviewAlbum(cleanDetail),
      detail: cleanDetail,
      primaryColor: palette.$1,
      secondaryColor: palette.$2,
      accentColor: palette.$3,
      coverGlyph: _audioPreviewGlyph(cleanTitle),
      lyricLines: _deriveAudioPreviewLyrics(cleanTitle, cleanDetail),
    );
  }

  final String title;
  final String artist;
  final String album;
  final String detail;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final String coverGlyph;
  final List<String> lyricLines;
}

const List<(Color, Color, Color)> _kAudioPreviewPalettes =
    <(Color, Color, Color)>[
      (Color(0xFF76815E), Color(0xFFBFC79A), Color(0xFFF4F0D7)),
      (Color(0xFF5C6E75), Color(0xFFA9C3BD), Color(0xFFE8F0E9)),
      (Color(0xFF765F73), Color(0xFFD2A9B8), Color(0xFFF4E5EA)),
      (Color(0xFF6F6B55), Color(0xFFD1C394), Color(0xFFF1E8C8)),
      (Color(0xFF59705C), Color(0xFFAEC8A8), Color(0xFFE8F3DF)),
    ];

String _normalizeAudioPreviewText(String value, {required String fallback}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return fallback;
  return trimmed
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(
        RegExp(r'\.(mp3|wav|m4a|aac|ogg|opus|flac)$', caseSensitive: false),
        '',
      )
      .trim();
}

String _deriveAudioPreviewArtist(String detail) {
  final leaf = _lastPathOrUrlSegment(detail);
  final segments = _normalizeAudioPreviewText(leaf, fallback: detail)
      .split(RegExp(r'[-_]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (segments.length >= 2 && segments.first.length <= 28) {
    return segments.first;
  }
  return 'OpenHand Audio';
}

String _deriveAudioPreviewAlbum(String detail) {
  final leaf = _lastPathOrUrlSegment(detail);
  final normalized = _normalizeAudioPreviewText(
    leaf,
    fallback: 'Preview Album',
  );
  return normalized.length <= 32 ? normalized : 'Preview Album';
}

String _lastPathOrUrlSegment(String value) {
  final parsed = Uri.tryParse(value);
  final segments = parsed?.pathSegments.where((segment) => segment.isNotEmpty);
  final lastSegment = segments == null || segments.isEmpty
      ? null
      : segments.last;
  if (lastSegment != null && lastSegment.trim().isNotEmpty) {
    return Uri.decodeComponent(lastSegment);
  }
  final normalized = value.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index >= 0 ? normalized.substring(index + 1) : normalized;
}

String _audioPreviewGlyph(String title) {
  final withoutEmoji = title
      .replaceAll(
        RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true),
        '',
      )
      .trim();
  if (withoutEmoji.isEmpty) return '♪';
  return withoutEmoji.characters.first.toUpperCase();
}

List<String> _deriveAudioPreviewLyrics(String title, String detail) {
  final leaf = _normalizeAudioPreviewText(
    _lastPathOrUrlSegment(detail),
    fallback: detail,
  );
  return <String>{
    title,
    leaf,
    'OpenHand media preview',
    'Waveform in motion',
    'Replay the moment clearly',
    'Keep the sound alive',
  }.where((line) => line.trim().isNotEmpty).take(6).toList(growable: false);
}

String _hexColor(Color color) {
  final value = color.toARGB32() & 0x00ffffff;
  return '#${value.toRadixString(16).padLeft(6, '0')}';
}

Color _mixColors(Color color, Color other, double colorWeight) {
  return Color.lerp(other, color, colorWeight.clamp(0.0, 1.0)) ?? color;
}

String _jsStringLiteral(String value) => jsonEncode(value);

String _jsStringArrayLiteral(Iterable<String> values) =>
    '[${values.map(_jsStringLiteral).join(',')}]';

/// 顶层入口：弹出预览弹窗。复用应用统一的 [showAnimatedDialog] 动画。
Future<void> showMediaPreviewDialog(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
}) {
  return showAnimatedDialog<void>(context: context, builder: builder);
}

String _dialogCurveToCss(DialogAnimationCurve curve) => switch (curve) {
  DialogAnimationCurve.easeInOut => 'ease-in-out',
  DialogAnimationCurve.easeOut => 'ease-out',
  DialogAnimationCurve.easeOutCubic => 'cubic-bezier(0.215, 0.61, 0.355, 1)',
  DialogAnimationCurve.easeInOutCubicEmphasized => 'cubic-bezier(0.2, 0, 0, 1)',
  DialogAnimationCurve.elasticOut => 'cubic-bezier(0.34, 1.56, 0.64, 1)',
  DialogAnimationCurve.bounceOut => 'cubic-bezier(0.22, 1.45, 0.36, 1)',
  DialogAnimationCurve.decelerate => 'cubic-bezier(0, 0, 0.2, 1)',
};
