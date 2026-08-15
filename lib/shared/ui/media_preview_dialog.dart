import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/support/silent_log.dart';
import '../../app/support/system_proxy.dart';
import '../../l10n/app_localizations.dart';
import '../net/http_redirect_utils.dart';
import '../net/http_response_utils.dart';
import '../util/async_concurrency.dart';
import '../util/bounded_directory_io.dart';
import '../util/bounded_file_io.dart';
import '../util/byte_size_format.dart';
import '../util/localized_text.dart';
import '../util/user_failure_message.dart';
import 'animated_dialog.dart';
import 'dialog_motion_css.dart';
import 'interactive_image_preview.dart';
import 'motion_preference.dart';
import 'native_audio_preview.dart';
import 'natural_image_size_resolver.dart';
import 'openhand_clipboard.dart';
import 'openhand_snack_bar.dart';
import 'openhand_video_player_web_styles.dart';


/// 通用图片 / 音频 / 视频预览弹窗。覆盖三种来源：
///   - `bytes`：内存 Uint8List（CDP 拉回的 base64 解码后的二进制）
///   - `network`：图片交给 [Image.network]，音频走原生播放器，视频走 webview
///   - `file`：本地文件路径
///
/// 与 home page 的 `_ImagePreviewDialog` 视觉一致：
///   - 弹窗外圈圆角 16，clipped Antialias
///   - 头部标题 + 关闭按钮 + 复制按钮
///   - 图片体积按真实宽高比动态贴合，四周 12px 统一留白；
///     不再因 `BoxFit.contain` 在固定容器内产生不均匀的上下 / 左右白边
///   - 音频走 Flutter 原生 UI 与跨平台音频插件，视频保留 webview_flutter 沙箱
enum MediaPreviewKind { image, audio, video }

const Map<String, String> _mediaExtensionsByMime = <String, String>{
  'audio/aac': 'aac',
  'audio/flac': 'flac',
  'audio/mp4': 'm4a',
  kAudioMpegMimeType: 'mp3',
  'audio/ogg': 'ogg',
  'audio/wav': 'wav',
  'audio/x-wav': 'wav',
  kVideoMp4MimeType: 'mp4',
  'video/quicktime': 'mov',
  'video/webm': 'webm',
  'video/x-matroska': 'mkv',
};
final Set<String> _activeMediaPreviewTempPaths = <String>{};

String _mediaTempPathKey(String path) => p.normalize(p.absolute(path));

String _mediaFileExtension(MediaPreviewKind kind, String? rawMimeType) {
  final mimeType = rawMimeType?.split(';').first.trim().toLowerCase();
  return _mediaExtensionsByMime[mimeType] ??
      (kind == MediaPreviewKind.video ? 'mp4' : 'mp3');
}

Future<void> _deleteTempFile(
  File file, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (timeout <= Duration.zero) return;
  final deadline = MonotonicDeadline(timeout, timeoutMessage: '删除媒体临时文件超时。');

  try {
    if (await file.exists().timeout(deadline.remaining())) {
      await file.delete().timeout(deadline.remaining());
    }
  } catch (error, stack) {
    silentLog('media_preview_dialog', '删除媒体临时文件', error, stack);
  } finally {
    deadline.stop();
  }
}

void _reportMediaTempWriteError(Object error, StackTrace stack) {
  silentLog('media_preview_dialog', '清理媒体临时文件', error, stack);
}

Future<void> _pruneMediaTempFiles(
  Directory directory, {
  required String filePrefix,
  required int maxRetainedFiles,
  required Duration maxAge,
  required Duration timeout,
  int scanLimit = 256,
}) async {
  if (timeout <= Duration.zero) return;
  final deadline = MonotonicDeadline(timeout, timeoutMessage: '清理媒体临时文件超时。');
  try {
    final listing = await listDirectoryBounded(
      directory,
      maxEntries: scanLimit,
      idleTimeout: timeout,
      totalTimeout: timeout,
    );
    final files =
        listing.entries
            .whereType<File>()
            .where((file) => p.basename(file.path).startsWith(filePrefix))
            .toList(growable: false)
          ..sort(
            (left, right) =>
                p.basename(right.path).compareTo(p.basename(left.path)),
          );
    final oldestAllowed = DateTime.now()
        .subtract(maxAge)
        .microsecondsSinceEpoch;
    for (var index = 0; index < files.length; index++) {
      if (_activeMediaPreviewTempPaths.contains(
        _mediaTempPathKey(files[index].path),
      )) {
        continue;
      }
      final name = p.basename(files[index].path);
      final stampEnd = name.indexOf('-', filePrefix.length);
      final stamp = stampEnd <= filePrefix.length
          ? null
          : int.tryParse(name.substring(filePrefix.length, stampEnd));
      if (index < maxRetainedFiles && stamp != null && stamp >= oldestAllowed) {
        continue;
      }
      final remaining = deadline.remainingOrNull();
      if (remaining == null) break;
      await _deleteTempFile(files[index], timeout: remaining);
    }
  } catch (error, stack) {
    silentLog('media_preview_dialog', '清理媒体临时文件', error, stack);
  } finally {
    deadline.stop();
  }
}

class MediaPreviewDialog extends StatefulWidget {
  const MediaPreviewDialog._({
    this.bytes,
    this.networkUrl,
    this.filePath,
    this.sourceUrl,
    this.mimeType,
    required this.kind,
    required this.title,
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
    sourceUrl: sourceUrl,
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
  final String? sourceUrl;
  final String? mimeType;
  final MediaPreviewKind kind;
  final String title;

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
  static const Duration _kClipboardTempMaxAge = Duration(days: 1);
  static const Duration _kClipboardTempCleanupTimeout = Duration(seconds: 2);
  static const int _kClipboardMaxBytes = 64 * kBytesPerMiB;
  static const int _kClipboardTempMaxFiles = 32;
  static const String _kClipboardTempDirectoryName = 'openhand-media-clipboard';
  static const String _kClipboardTempFilePrefix = 'media-';
  static int _clipboardTempSerial = 0;

  late final NaturalImageSizeResolver _imageSize = NaturalImageSizeResolver(
    onResolved: () {
      if (mounted) setState(() {});
    },
  );
  bool _copying = false;

  @override
  void initState() {
    super.initState();
    if (widget.kind == MediaPreviewKind.image) {
      _imageSize.resolve(_imageProvider());
    }
  }

  @override
  void dispose() {
    _imageSize.dispose();
    super.dispose();
  }

  ImageProvider? _imageProvider() {
    final bytes = widget.bytes;
    if (bytes != null) return MemoryImage(bytes);
    final filePath = widget.filePath;
    if (filePath != null) return FileImage(File(filePath));
    final networkUrl = widget.networkUrl;
    if (networkUrl != null) return NetworkImage(networkUrl);
    return null;
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
    final motionEnabled = openHandTickerMotionEnabled(context);
    final motionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final l10n = AppLocalizations.of(context)!;

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
      final natural = _imageSize.size;
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
      bodyW = math.min(kNativeAudioPreviewPreferredSize.width, maxBodyW);
      bodyH = math.min(kNativeAudioPreviewPreferredSize.height, maxBodyH);
    } else {
      bodyW = math.min(960.0, maxBodyW);
      bodyH = math.min(640.0, maxBodyH);
    }

    final dialogW = (bodyW + padding * 2).clamp(_kMinDialogW, maxDialogW);

    return buildOpenHandDialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.all(_kInsetPadding),
      width: dialogW,
      maxHeight: maxDialogH,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandRadius16)),
      child: AnimatedSize(
        duration: motionEnabled
            ? motionSettings.entranceDuration
            : Duration.zero,
        curve: motionSettings.curve.curve,
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
                      kOpenHandHGap10,
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.commonCopy,
                        onPressed: _copying
                            ? null
                            : () => _copyToClipboard(context),
                        icon: const Icon(Icons.content_copy_outlined),
                      ),
                      kOpenHandHGap8,
                      IconButton(
                        tooltip: l10n.commonClose,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: Padding(
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
                              motionCurveCss: openHandDialogAnimationCurveCss(
                                motionSettings.curve,
                              ),
                              motionCurve: motionSettings.curve.curve,
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
    final l10n = AppLocalizations.of(context)!;
    try {
      if (widget.kind == MediaPreviewKind.image) {
        final copiedImageData = await _copyImageSource();
        if (!context.mounted) return;
        _showCopySnack(
          context,
          message: copiedImageData
              ? l10n.mediaPreviewImageCopied
              : l10n.mediaPreviewImageFileOrPathCopied,
        );
        return;
      }
      final filePath = widget.filePath;
      if (filePath != null) {
        final ok = await _copyFilePathToClipboard(filePath);
        if (!context.mounted) return;
        _showCopySnack(
          context,
          message: ok
              ? l10n.mediaPreviewMediaFileCopied
              : l10n.mediaPreviewDirectCopyUnavailablePathCopied,
        );
        return;
      }
      final url = widget.networkUrl ?? widget.sourceUrl;
      if (url != null) {
        await setOpenHandClipboardText(url, timeout: _kClipboardTimeout);
        if (!context.mounted) return;
        _showCopySnack(context, message: l10n.mediaPreviewMediaUrlCopied);
        return;
      }
      final bytes = widget.bytes;
      if (bytes != null) {
        final tempPath = await _writeBytesToClipboardTempFile(bytes);
        final ok = await _copyFilePathToClipboard(tempPath);
        if (!context.mounted) return;
        _showCopySnack(
          context,
          message: ok
              ? l10n.mediaPreviewMediaFileCopied
              : l10n.mediaPreviewDirectCopyUnavailableTempPathCopied,
        );
        return;
      }
      throw const FileSystemException('媒体源不可用。');
    } catch (error, stack) {
      silentLog('media_preview_dialog', '复制媒体内容', error, stack);
      final url = widget.networkUrl ?? widget.sourceUrl;
      if (url != null) {
        try {
          await setOpenHandClipboardText(url, timeout: _kClipboardTimeout);
          if (!context.mounted) return;
          _showCopySnack(
            context,
            message: l10n.mediaPreviewDataCopyFailedUrlCopied,
          );
          return;
        } catch (fallbackError, fallbackStack) {
          silentLog(
            'media_preview_dialog',
            '复制媒体来源地址',
            fallbackError,
            fallbackStack,
          );
        }
      }
      if (!context.mounted) return;
      final detail = userFailureMessage(
        error,
        fallback: openHandLocalizedText(
          context,
          zh: '无法复制媒体内容，请稍后重试。',
          zhHant: '無法複製媒體內容，請稍後重試。',
          en: 'Unable to copy the media. Please try again later.',
          fr: 'Impossible de copier le média. Réessayez plus tard.',
          de: 'Das Medium konnte nicht kopiert werden. Bitte später erneut versuchen.',
          ja: 'メディアをコピーできませんでした。しばらくしてから再試行してください。',
        ),
      );
      _showCopySnack(
        context,
        message: l10n.mediaPreviewCopyFailed(detail),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<bool> _copyImageSource() async {
    final bytes = widget.bytes;
    if (bytes != null) {
      if (bytes.length > _kClipboardMaxBytes) {
        throw const FileSystemException('图片数据超过剪贴板容量上限。');
      }
      await writeOpenHandClipboardImage(bytes);
      return true;
    }
    final filePath = widget.filePath;
    if (filePath != null) {
      final file = File(filePath);
      try {
        await writeOpenHandClipboardImage(
          await readBoundedFileBytes(
            file,
            maxBytes: _kClipboardMaxBytes,
            idleTimeout: _kClipboardTimeout,
            totalTimeout: _kClipboardTimeout,
          ),
        );
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
      await writeOpenHandClipboardImage(downloaded);
      return true;
    }
    throw const FileSystemException('图片源不可用。');
  }

  Future<bool> _copyFilePathToClipboard(String filePath) async {
    var ok = false;
    try {
      ok = await writeOpenHandClipboardFiles(<String>[filePath]);
    } catch (_) {
      ok = false;
    } finally {
      await setOpenHandClipboardText(filePath, timeout: _kClipboardTimeout);
    }
    return ok;
  }

  Future<Uint8List> _downloadNetworkBytes(
    Uri uri, {
    String? expectedPrimaryType,
  }) async {
    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: _kNetworkTimeout,
    );
    try {
      return fetchBoundedHttpBytes(
        client: client,
        uri: uri,
        maxBytes: _kClipboardMaxBytes,
        openTimeout: _kNetworkTimeout,
        idleTimeout: _kNetworkTimeout,
        totalTimeout: _kNetworkTimeout,
        expectedPrimaryType: expectedPrimaryType,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _writeBytesToClipboardTempFile(Uint8List bytes) async {
    if (bytes.length > _kClipboardMaxBytes) {
      throw const FileSystemException('媒体数据超过剪贴板容量上限。');
    }
    final dir = Directory(
      p.join(Directory.systemTemp.path, _kClipboardTempDirectoryName),
    );
    await dir.create(recursive: true).timeout(_kClipboardTimeout);
    await _pruneMediaTempFiles(
      dir,
      filePrefix: _kClipboardTempFilePrefix,
      maxRetainedFiles: _kClipboardTempMaxFiles - 1,
      maxAge: _kClipboardTempMaxAge,
      timeout: _kClipboardTempCleanupTimeout,
    );
    final ext = _mediaFileExtension(widget.kind, widget.mimeType);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final serial = _clipboardTempSerial++;
    final file = File(
      p.join(dir.path, '$_kClipboardTempFilePrefix$stamp-$pid-$serial.$ext'),
    );
    await writeTemporaryFileBytesBounded(
      file,
      bytes,
      timeout: _kClipboardTimeout,
      onSecondaryError: _reportMediaTempWriteError,
    );
    return file.path;
  }

  void _showCopySnack(
    BuildContext context, {
    required String message,
    bool isError = false,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    OpenHandSnackBar.show(
      context,
      messenger,
      isError
          ? OpenHandSnackBar.error(context, message, maxLines: 2)
          : OpenHandSnackBar.success(context, message),
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
          borderRadius: BorderRadius.circular(kOpenHandRadius12),
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
    required this.motionCurve,
  });

  final String title;
  final Uint8List? bytes;
  final String? networkUrl;
  final String? filePath;
  final String? mimeType;
  final MediaPreviewKind kind;
  final int motionDurationMs;
  final String motionCurveCss;
  final Curve motionCurve;

  @override
  State<_MediaPlayerSurface> createState() => _MediaPlayerSurfaceState();
}

class _MediaPlayerSurfaceState extends State<_MediaPlayerSurface> {
  static const int _kInlineDataUrlMaxBytes = 8 * kBytesPerMiB;
  static const int _kTempMediaMaxBytes = 256 * kBytesPerMiB;
  static const int _kControlsAutoHideMs = 2600;
  static const int _kPreviewTempMaxFiles = 32;
  static const Duration _kBootstrapOperationTimeout = Duration(seconds: 15);
  static const Duration _kPreviewTempMaxAge = Duration(days: 1);
  static const Duration _kPreviewTempCleanupTimeout = Duration(seconds: 2);
  static const String _kPreviewTempDirectoryName = 'openhand-media-preview';
  static const String _kPreviewTempFilePrefix = 'preview-';
  static int _previewTempSerial = 0;

  WebViewController? _controller;
  String? _tempHtmlPath;
  String? _tempMediaPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.kind == MediaPreviewKind.video) {
      _bootstrapVideo();
    }
  }

  Future<void> _bootstrapVideo() async {
    final deadline = MonotonicDeadline(
      _kBootstrapOperationTimeout,
      timeoutMessage: '视频预览初始化超时。',
    );

    try {
      final normalizedMime = widget.mimeType
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      final mime = normalizedMime == null || normalizedMime.isEmpty
          ? kVideoMp4MimeType
          : normalizedMime;
      final tempDirectory = Directory(
        p.join(Directory.systemTemp.path, _kPreviewTempDirectoryName),
      );
      await tempDirectory.create(recursive: true).timeout(deadline.remaining());
      await _pruneMediaTempFiles(
        tempDirectory,
        filePrefix: _kPreviewTempFilePrefix,
        maxRetainedFiles: _kPreviewTempMaxFiles - 2,
        maxAge: _kPreviewTempMaxAge,
        timeout: _kPreviewTempCleanupTimeout,
      );
      if (!mounted) return;
      String src;
      if (widget.networkUrl != null) {
        src = widget.networkUrl!;
      } else if (widget.filePath != null) {
        src = Uri.file(widget.filePath!).toString();
      } else if (widget.bytes != null) {
        if (widget.bytes!.lengthInBytes <= _kInlineDataUrlMaxBytes) {
          src = 'data:$mime;base64,${base64Encode(widget.bytes!)}';
        } else {
          if (widget.bytes!.lengthInBytes > _kTempMediaMaxBytes) {
            throw const FileSystemException('视频数据超过预览容量上限。');
          }
          final mediaFile = _newPreviewTempFile(
            tempDirectory,
            _mediaFileExtension(widget.kind, widget.mimeType),
          );
          await writeTemporaryFileBytesBounded(
            mediaFile,
            widget.bytes!,
            timeout: deadline.remaining(),
            onSecondaryError: _reportMediaTempWriteError,
          );
          _tempMediaPath = mediaFile.path;
          _activeMediaPreviewTempPaths.add(_mediaTempPathKey(mediaFile.path));
          if (!mounted) {
            await _cleanupTempFiles();
            return;
          }
          src = Uri.file(mediaFile.path).toString();
        }
      } else {
        if (!mounted) return;
        setState(
          () => _error = AppLocalizations.of(context)!.mediaPreviewNoSource,
        );
        return;
      }
      final html = _buildVideoPlayerHtml(src: src);
      final htmlFile = _newPreviewTempFile(tempDirectory, 'html');
      await writeTemporaryFileTextBounded(
        htmlFile,
        html,
        timeout: deadline.remaining(),
        onSecondaryError: _reportMediaTempWriteError,
      );
      _tempHtmlPath = htmlFile.path;
      _activeMediaPreviewTempPaths.add(_mediaTempPathKey(htmlFile.path));
      if (!mounted) {
        await _cleanupTempFiles();
        return;
      }
      final controller = WebViewController();
      await controller
          .setJavaScriptMode(JavaScriptMode.unrestricted)
          .timeout(deadline.remaining());
      if (!mounted) {
        await _cleanupTempFiles();
        return;
      }
      await controller
          .setBackgroundColor(const Color(0xFF0F0F10))
          .timeout(deadline.remaining());
      if (!mounted) {
        await _cleanupTempFiles();
        return;
      }
      await controller
          .addJavaScriptChannel(
            'OpenHandMediaPreview',
            onMessageReceived: (_) => _requestDialogClose(),
          )
          .timeout(deadline.remaining());
      if (!mounted) {
        await _cleanupTempFiles();
        return;
      }
      await controller.loadFile(htmlFile.path).timeout(deadline.remaining());
      if (!mounted) {
        await _cleanupTempFiles();
        return;
      }
      setState(() => _controller = controller);
    } catch (error, stack) {
      await _cleanupTempFiles();
      silentLog('media_preview_dialog', '初始化视频预览 WebView', error, stack);
      if (!mounted) return;
      setState(
        () => _error = userFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '视频预览初始化失败，请重试。',
            zhHant: '影片預覽初始化失敗，請重試。',
            en: 'Failed to initialize the video preview. Please try again.',
            fr: 'Échec de l’initialisation de l’aperçu vidéo. Réessayez.',
            de: 'Die Videovorschau konnte nicht initialisiert werden. Bitte erneut versuchen.',
            ja: '動画プレビューを初期化できませんでした。再試行してください。',
          ),
        ),
      );
    } finally {
      deadline.stop();
    }
  }

  File _newPreviewTempFile(Directory directory, String extension) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final serial = _previewTempSerial++;
    return File(
      p.join(
        directory.path,
        '$_kPreviewTempFilePrefix$stamp-$pid-$serial.$extension',
      ),
    );
  }

  Future<void> _cleanupTempFiles() async {
    final htmlPath = _tempHtmlPath;
    final mediaPath = _tempMediaPath;
    _tempHtmlPath = null;
    _tempMediaPath = null;
    if (htmlPath != null) {
      _activeMediaPreviewTempPaths.remove(_mediaTempPathKey(htmlPath));
    }
    if (mediaPath != null) {
      _activeMediaPreviewTempPaths.remove(_mediaTempPathKey(mediaPath));
    }
    await Future.wait<void>(<Future<void>>[
      if (htmlPath != null) _deleteTempFile(File(htmlPath)),
      if (mediaPath != null) _deleteTempFile(File(mediaPath)),
    ]);
  }

  void _requestDialogClose() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    unawaited(Navigator.of(context).maybePop());
  }

  String _buildVideoPlayerHtml({required String src}) {
    final durationMs = widget.motionDurationMs
        .clamp(0, DialogAnimationSettings.maxDurationMs)
        .toInt();
    final safeCurve = openHandCssTimingFunctionOrDefault(widget.motionCurveCss);
    final escapedSrc = const HtmlEscape(HtmlEscapeMode.attribute).convert(src);
    return '''
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--oh-motion-duration:__DURATION__ms;--oh-motion-curve:__CURVE__;--oh-control-bg:rgba(18,18,20,.72);--oh-control-border:rgba(255,255,255,.16);--oh-control-text:#fff;--oh-track:rgba(255,255,255,.22);--oh-track-fill:#fff}
html,body{margin:0;padding:0;background:#0f0f10;height:100%;overflow:hidden;color:#fff;font:13px/1.4 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei","Noto Sans CJK SC","Segoe UI",Roboto,sans-serif}
button,input{font:inherit}
.media-shell{position:relative;width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:#0f0f10;user-select:none;overflow:hidden;isolation:isolate}
${openHandVideoPlayerControlsCss(compactBreakpointPx: 420, compactHorizontalInsetPx: 20)}
</style></head><body>
<div id="shell" class="media-shell controls-visible__NO_MOTION__" tabindex="0">
  <video id="media" preload="metadata" autoplay playsinline src="__SRC__"></video>
${openHandVideoPlayerControlsHtml(trailingActionId: 'fullscreen', trailingActionLabel: 'Fullscreen')}
</div>
<script>
(() => {
  const AUTO_HIDE_MS = __AUTO_HIDE__;
  $openHandVideoPlayerElementBindingsJavaScript
  const fullscreen = document.getElementById('fullscreen');
  if (!media || !play || !rewind || !forward || !progress || !current || !duration || !volume || !mute || !volumeGroup || !playMode) {
    requestClose();
    return;
  }
  let hideTimer = 0;
  let dragging = false;
  let volumeActive = false;
  let looping = false;
  ${openHandVideoPlayerIconsJavaScript()}
  rewind.innerHTML = icon.rewind;
  forward.innerHTML = icon.forward;
  if (fullscreen) fullscreen.innerHTML = icon.fullscreen;
  function requestClose() { try { window.OpenHandMediaPreview?.postMessage('close'); } catch (_) {} }
  $openHandVideoPlayerScriptUtilities
  $openHandVideoPlayerVisibilityJavaScript
  $openHandVideoPlayerStateSyncJavaScript
  function setVolumeActive(active) {
    volumeActive = active;
    shell.classList.toggle('volume-open', active);
    if (active) showControls(true); else scheduleHide();
  }
  play.addEventListener('click', () => {
    if (media.paused) media.play().catch(() => showControls(true)); else media.pause();
    showControls(true);
  });
  rewind.addEventListener('click', () => seekBy(-15));
  forward.addEventListener('click', () => seekBy(15));
  progress.addEventListener('pointerdown', (event) => { dragging = true; progress.setPointerCapture?.(event.pointerId); showControls(true); });
  progress.addEventListener('pointerup', (event) => { dragging = false; progress.releasePointerCapture?.(event.pointerId); scheduleHide(); });
  progress.addEventListener('pointercancel', () => { dragging = false; scheduleHide(); });
  progress.addEventListener('input', () => {
    const dur = Number.isFinite(media.duration) ? media.duration : 0;
    if (dur > 0) media.currentTime = (Number(progress.value) / 1000) * dur;
    updateTime();
    showControls(true);
  });
  volumeGroup.addEventListener('pointerenter', () => setVolumeActive(true));
  volumeGroup.addEventListener('pointerleave', () => setVolumeActive(false));
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
    setVolumeActive(true);
  });
  playMode.addEventListener('click', () => { looping = !looping; updatePlayMode(); showControls(true); });
  if (fullscreen) {
    fullscreen.addEventListener('click', () => {
      if (document.fullscreenElement) document.exitFullscreen?.(); else shell.requestFullscreen?.().catch(() => {});
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
    if (event.key === 'Escape') { event.preventDefault(); requestClose(); }
    else if (event.key === ' ' || event.key === 'Enter') { event.preventDefault(); play.click(); }
    else if (event.key === 'ArrowLeft') { event.preventDefault(); seekBy(-5); }
    else if (event.key === 'ArrowRight') { event.preventDefault(); seekBy(5); }
    else if (event.key.toLowerCase() === 'm') { event.preventDefault(); mute.click(); }
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
  media.addEventListener('ended', () => { updatePlayState(); showControls(true); });
  media.addEventListener('volumechange', updateVolume);
  window.addEventListener('beforeunload', () => clearHideTimer());
  updatePlayMode();
  updatePlayState();
  updateTime();
  updateVolume();
  media.play?.().catch(() => updatePlayState());
})();
</script>
</body></html>
'''
        .replaceAll('__DURATION__', '$durationMs')
        .replaceAll('__CURVE__', safeCurve)
        .replaceAll('__NO_MOTION__', durationMs == 0 ? ' no-motion' : '')
        .replaceAll('__SRC__', escapedSrc)
        .replaceAll('__AUTO_HIDE__', '$_kControlsAutoHideMs');
  }

  @override
  void dispose() {
    unawaited(_cleanupTempFiles());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.kind == MediaPreviewKind.audio) {
      return NativeAudioPreview(
        title: widget.title,
        source: _nativeAudioSource,
        meta: _nativeAudioMeta,
        autoplay: true,
        motionDuration: Duration(
          milliseconds: widget.motionDurationMs.clamp(
            0,
            DialogAnimationSettings.maxDurationMs,
          ),
        ),
        motionCurve: widget.motionCurve,
      );
    }
    if (_error != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(kOpenHandRadius12),
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
      borderRadius: BorderRadius.circular(kOpenHandRadius12),
      child: WebViewWidget(controller: _controller!),
    );
  }

  NativeAudioPreviewSource get _nativeAudioSource {
    final mimeType = widget.mimeType ?? kAudioMpegMimeType;
    final bytes = widget.bytes;
    if (bytes != null) {
      return NativeAudioPreviewSource.bytes(
        bytes: bytes,
        mimeType: mimeType,
        detail: widget.networkUrl ?? widget.filePath ?? widget.title,
      );
    }
    final filePath = widget.filePath;
    if (filePath != null) {
      return NativeAudioPreviewSource.file(
        filePath: filePath,
        mimeType: mimeType,
        detail: filePath,
      );
    }
    final networkUrl = widget.networkUrl;
    if (networkUrl != null) {
      return NativeAudioPreviewSource.network(
        url: networkUrl,
        mimeType: mimeType,
        detail: networkUrl,
      );
    }
    return NativeAudioPreviewSource.network(
      url: '',
      mimeType: mimeType,
      detail: widget.title,
    );
  }

  NativeAudioVisualMeta get _nativeAudioMeta => NativeAudioVisualMeta.fromText(
    title: widget.title,
    detail:
        widget.filePath ?? widget.networkUrl ?? widget.mimeType ?? 'OpenHand',
  );
}
