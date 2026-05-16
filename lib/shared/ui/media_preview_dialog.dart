import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'animated_dialog.dart';

/// 通用图片 / 音频 / 视频预览弹窗。覆盖三种来源：
///   - `bytes`：内存 Uint8List（CDP 拉回的 base64 解码后的二进制）
///   - `network`：URL 直接交给 [Image.network] 或 webview 内嵌 `<audio>` / `<video>`
///   - `file`：本地文件路径
///
/// 与 home page 的 `_ImagePreviewDialog` 视觉一致：圆角 16、四周 12px padding、
/// 头部标题 + 关闭按钮 + 复制 URL 按钮、主体支持 [InteractiveViewer] 缩放拖动；
/// 音视频走 webview_flutter 沙箱，避免引入新依赖。
///
/// 同样的弹窗也用于 web_reverse 调试面板，避免重复造轮子。
enum MediaPreviewKind { image, audio, video }

class MediaPreviewDialog extends StatelessWidget {
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
  }) =>
      MediaPreviewDialog._(
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
  }) =>
      MediaPreviewDialog._(
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
  }) =>
      MediaPreviewDialog._(
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final maxW = viewport.width - 48;
    final maxH = viewport.height - 48;
    final isZh =
        Localizations.localeOf(context).languageCode.startsWith('zh');
    return Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
              child: Row(
                children: [
                  Icon(
                    switch (kind) {
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
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (onCopyUrl != null)
                    IconButton(
                      tooltip: isZh ? '复制源 URL' : 'Copy source URL',
                      onPressed: () {
                        onCopyUrl!();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(isZh ? '已复制' : 'Copied'),
                          duration: const Duration(seconds: 1),
                        ));
                      },
                      icon: const Icon(Icons.link_rounded),
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
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxW - 24,
                  maxHeight: maxH - 80,
                ),
                child: kind == MediaPreviewKind.image
                    ? InteractiveViewer(
                        maxScale: 6,
                        child: _buildImage(context),
                      )
                    : SizedBox(
                        width: (maxW - 24).clamp(320, 960),
                        height: kind == MediaPreviewKind.audio
                            ? 120
                            : (maxH - 80).clamp(240, 640),
                        child: _MediaPlayerSurface(
                          bytes: bytes,
                          networkUrl: networkUrl,
                          filePath: filePath,
                          mimeType: mimeType,
                          kind: kind,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    if (bytes != null) {
      return Image.memory(
        bytes!,
        fit: BoxFit.contain,
        errorBuilder: (c, _, _) => _errorBox(c),
      );
    }
    if (networkUrl != null) {
      return Image.network(
        networkUrl!,
        fit: BoxFit.contain,
        errorBuilder: (c, _, _) => _errorBox(c),
      );
    }
    if (filePath != null) {
      return Image.network(
        Uri.file(filePath!).toString(),
        fit: BoxFit.contain,
        errorBuilder: (c, _, _) => _errorBox(c),
      );
    }
    return _errorBox(context);
  }

  Widget _errorBox(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 320,
      height: 200,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Icon(Icons.broken_image_outlined,
              size: 48, color: cs.error),
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
      final mime = (widget.mimeType ??
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
        if (widget.bytes!.lengthInBytes <= 8 * 1024 * 1024) {
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
      final html = '''
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
      // ignore: avoid_print
      print('media_preview bootstrap fail: $error\n$stack');
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
