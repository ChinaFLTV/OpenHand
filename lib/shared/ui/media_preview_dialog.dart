import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/support/silent_log.dart';
import '../util/byte_size_format.dart';
import 'animated_dialog.dart';
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
    final viewport = MediaQuery.sizeOf(context);
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

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
      bodyW = maxBodyW.clamp(320.0, 960.0);
      bodyH = 120;
    } else {
      bodyW = maxBodyW.clamp(320.0, 960.0);
      bodyH = maxBodyH.clamp(240.0, 640.0);
    }

    final dialogW = (bodyW + padding * 2).clamp(_kMinDialogW, maxDialogW);

    return Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.all(_kInsetPadding),
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
                        ? InteractiveViewer(
                            maxScale: 6,
                            child: _buildImage(context),
                          )
                        : _MediaPlayerSurface(
                            bytes: widget.bytes,
                            networkUrl: widget.networkUrl,
                            filePath: widget.filePath,
                            mimeType: widget.mimeType,
                            kind: widget.kind,
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    OpenHandSnackBar.show(
      context,
      messenger,
      isError
          ? OpenHandSnackBar.error(context, isZh ? zh : en, maxLines: 2)
          : OpenHandSnackBar.success(context, isZh ? zh : en),
    );
  }

  Widget _buildImage(BuildContext context) {
    if (widget.bytes != null) {
      return Image.memory(
        widget.bytes!,
        fit: BoxFit.contain,
        errorBuilder: (c, _, _) => _errorBox(c),
      );
    }
    if (widget.networkUrl != null) {
      return Image.network(
        widget.networkUrl!,
        fit: BoxFit.contain,
        errorBuilder: (c, _, _) => _errorBox(c),
      );
    }
    if (widget.filePath != null) {
      return Image.file(
        File(widget.filePath!),
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
/// 网络 URL 直接挂到 `src`。WebView 的内置控件已经覆盖播放 / 进度 / 全屏。
class _MediaPlayerSurface extends StatefulWidget {
  const _MediaPlayerSurface({
    required this.bytes,
    required this.networkUrl,
    required this.filePath,
    required this.mimeType,
    required this.kind,
  });

  final Uint8List? bytes;
  final String? networkUrl;
  final String? filePath;
  final String? mimeType;
  final MediaPreviewKind kind;

  @override
  State<_MediaPlayerSurface> createState() => _MediaPlayerSurfaceState();
}

class _MediaPlayerSurfaceState extends State<_MediaPlayerSurface> {
  WebViewController? _controller;
  String? _tempHtmlPath;
  String? _tempMediaPath;
  String? _error;

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
        if (widget.bytes!.lengthInBytes <= 8 * kBytesPerMiB) {
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
      final tag = widget.kind == MediaPreviewKind.video ? 'video' : 'audio';
      final html =
          '''
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
html,body{margin:0;padding:0;background:#0f0f10;height:100%;display:flex;align-items:center;justify-content:center;color:#fff;font:13px/1.4 -apple-system,Segoe UI,Roboto,sans-serif}
$tag{width:100%;max-height:100%;outline:none;border-radius:10px;background:#000}
</style></head><body>
<$tag controls autoplay src="${_jsEscape(src)}"></$tag>
</body></html>
''';
      final dir = Directory.systemTemp;
      final f = File(
        '${dir.path}/oh-media-host-${DateTime.now().microsecondsSinceEpoch}.html',
      );
      await f.writeAsString(html);
      _tempHtmlPath = f.path;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0F0F10))
        ..loadFile(f.path);
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error, stack) {
      silentLog('media_preview', 'bootstrap webview host', error, stack);
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  String _jsEscape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

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

/// 顶层入口：弹出预览弹窗。复用应用统一的 [showAnimatedDialog] 动画。
Future<void> showMediaPreviewDialog(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
}) {
  return showAnimatedDialog<void>(context: context, builder: builder);
}
