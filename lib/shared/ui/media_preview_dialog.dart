import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/support/silent_log.dart';
import '../../app/support/system_proxy.dart';
import '../../l10n/app_localizations.dart';
import '../db/atomic_file_operations.dart';
import '../net/bounded_http_request.dart';
import '../net/http_redirect_utils.dart';
import '../net/http_response_utils.dart';
import '../net/http_status_utils.dart';
import '../util/async_concurrency.dart';
import '../util/bounded_file_io.dart';
import '../util/byte_size_format.dart';
import '../util/input_value_parsing.dart';
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
  kImagePngMimeType: 'png',
  kImageJpegMimeType: 'jpg',
  kImageGifMimeType: 'gif',
  kImageWebpMimeType: 'webp',
  kImageSvgXmlMimeType: 'svg',
  kImageBmpMimeType: 'bmp',
  kAudioAacMimeType: 'aac',
  kAudioFlacMimeType: 'flac',
  'audio/mp4': 'm4a',
  kAudioMpegMimeType: 'mp3',
  kAudioOggMimeType: 'ogg',
  kAudioWavMimeType: 'wav',
  'audio/x-wav': 'wav',
  kVideoMp4MimeType: 'mp4',
  kVideoQuickTimeMimeType: 'mov',
  kVideoWebmMimeType: 'webm',
  kVideoMatroskaMimeType: 'mkv',
};

String _mediaFileExtension(MediaPreviewKind kind, String? rawMimeType) {
  final mimeType = rawMimeType?.split(';').first.trim().toLowerCase();
  return _mediaExtensionsByMime[mimeType] ??
      switch (kind) {
        MediaPreviewKind.image => 'png',
        MediaPreviewKind.audio => 'mp3',
        MediaPreviewKind.video => 'mp4',
      };
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
  static const Duration _kSaveNetworkIdleTimeout = Duration(seconds: 30);
  static const Duration _kSaveImageTotalTimeout = Duration(minutes: 10);
  static const Duration _kSaveAudioTotalTimeout = Duration(minutes: 15);
  static const Duration _kSaveVideoTotalTimeout = Duration(minutes: 30);
  static const Duration _kClipboardTempMaxAge = Duration(days: 1);
  static const Duration _kClipboardTempCleanupTimeout = Duration(seconds: 2);
  static const int _kClipboardMaxBytes = 64 * kBytesPerMiB;
  static const int _kSaveImageMaxBytes = 256 * kBytesPerMiB;
  static const int _kSaveAudioMaxBytes = 512 * kBytesPerMiB;
  static const int _kSaveVideoMaxBytes = 2 * kBytesPerGiB;
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
  bool _saving = false;
  bool _imageErrorLogged = false;

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
    if (_isSvgImage) return null;
    final bytes = widget.bytes;
    if (bytes != null) return MemoryImage(bytes);
    final filePath = widget.filePath;
    if (filePath != null) return FileImage(File(filePath));
    final networkUrl = widget.networkUrl;
    if (networkUrl != null) return NetworkImage(networkUrl);
    return null;
  }

  bool get _isSvgImage {
    if (widget.kind != MediaPreviewKind.image) return false;
    final mimeType = widget.mimeType?.split(';').first.trim().toLowerCase();
    if (mimeType == kImageSvgXmlMimeType) return true;
    final source = widget.filePath ?? widget.networkUrl ?? widget.title;
    final uri = Uri.tryParse(source);
    final sourcePath = uri != null && uri.path.isNotEmpty ? uri.path : source;
    return p.extension(sourcePath).toLowerCase() == '.svg';
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
      ),
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
                        tooltip: l10n.commonSave,
                        onPressed: _copying || _saving
                            ? null
                            : () => _saveToFile(context),
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_alt_rounded),
                      ),
                      kOpenHandHGap8,
                      IconButton(
                        tooltip: l10n.commonCopy,
                        onPressed: _copying || _saving
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

  Future<void> _saveToFile(BuildContext context) async {
    if (_copying || _saving) return;
    setState(() => _saving = true);
    try {
      final suggestedName = _suggestedSaveName();
      final extension = p.extension(suggestedName).replaceFirst('.', '');
      final acceptedTypeGroups =
          RegExp(r'^[a-zA-Z0-9]{1,12}$').hasMatch(extension)
          ? <XTypeGroup>[
              XTypeGroup(
                label: switch (widget.kind) {
                  MediaPreviewKind.image => 'Images',
                  MediaPreviewKind.audio => 'Audio',
                  MediaPreviewKind.video => 'Videos',
                },
                extensions: <String>[extension],
              ),
            ]
          : <XTypeGroup>[];
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: acceptedTypeGroups,
      );
      if (location == null || !context.mounted) return;
      await _writeMediaSource(File(location.path));
      if (!context.mounted) return;
      _showMediaSnack(
        context,
        message: openHandLocalizedText(
          context,
          zh: '已保存到：${location.path}',
          en: 'Saved to: ${location.path}',
        ),
      );
    } catch (error, stack) {
      silentLog('media_preview_dialog', '保存媒体文件', error, stack);
      if (!context.mounted) return;
      _showMediaSnack(
        context,
        message: userFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '无法保存媒体文件，请稍后重试。',
            en: 'Unable to save the media file. Please try again later.',
          ),
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _suggestedSaveName() {
    String fileNameFrom(String value) {
      final normalized = value.replaceAll(r'\', '/');
      final name = p.posix
          .basename(normalized)
          .trim()
          .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
      return name == '.' || name == '/' ? '' : name;
    }

    var name = '';
    final filePath = widget.filePath;
    if (filePath != null) name = fileNameFrom(filePath);
    final url = widget.networkUrl ?? widget.sourceUrl;
    if (name.isEmpty && url != null) {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.path.isNotEmpty) {
        name = fileNameFrom(decodeUriComponentOrOriginal(uri.path));
      }
    }
    if (name.isEmpty) name = fileNameFrom(widget.title);
    if (name.isEmpty) {
      name = switch (widget.kind) {
        MediaPreviewKind.image => 'image',
        MediaPreviewKind.audio => 'audio',
        MediaPreviewKind.video => 'video',
      };
    }
    if (p.extension(name).isEmpty) {
      name = '$name.${_mediaFileExtension(widget.kind, widget.mimeType)}';
    }
    return name;
  }

  Future<void> _writeMediaSource(File destination) async {
    final bytes = widget.bytes;
    if (bytes != null) {
      await writeBytesFileAtomically(destination, bytes);
      return;
    }
    final filePath = widget.filePath;
    if (filePath != null) {
      final source = File(filePath);
      final stat = await source.stat().timeout(_kClipboardTimeout);
      if (stat.type != FileSystemEntityType.file) {
        throw FileSystemException('媒体源不是普通文件。', filePath);
      }
      if (p.equals(p.absolute(source.path), p.absolute(destination.path))) {
        return;
      }
      await copyFileAtomically(
        source,
        destination,
        maxBytes: math.max(1, stat.size),
      );
      return;
    }
    final url = widget.networkUrl ?? widget.sourceUrl;
    if (url != null) {
      await _downloadNetworkFile(Uri.parse(url), destination);
      return;
    }
    throw const FileSystemException('媒体源不可用。');
  }

  int get _saveMaxBytes => switch (widget.kind) {
    MediaPreviewKind.image => _kSaveImageMaxBytes,
    MediaPreviewKind.audio => _kSaveAudioMaxBytes,
    MediaPreviewKind.video => _kSaveVideoMaxBytes,
  };

  Duration get _saveTotalTimeout => switch (widget.kind) {
    MediaPreviewKind.image => _kSaveImageTotalTimeout,
    MediaPreviewKind.audio => _kSaveAudioTotalTimeout,
    MediaPreviewKind.video => _kSaveVideoTotalTimeout,
  };

  Future<void> _downloadNetworkFile(Uri uri, File destination) async {
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
      throw const FormatException('仅支持有效的 HTTP(S) 媒体地址。');
    }
    final deadline = MonotonicDeadline(
      _saveTotalTimeout,
      timeoutMessage: '媒体文件保存超过总时限。',
    );
    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: deadline.limit(_kNetworkTimeout),
    );
    try {
      final request = await openHttpClientRequestBounded(
        () => client.getUrl(uri),
        timeout: deadline.limit(_kNetworkTimeout),
        timeoutMessage: '媒体下载请求打开超时。',
      );
      final response = await closeHttpClientRequestBounded(
        request,
        timeout: deadline.limit(_kNetworkTimeout),
        timeoutMessage: '媒体下载响应头获取超时。',
      );
      var consumptionStarted = false;
      try {
        if (isHttpFailureStatus(response.statusCode)) {
          throw HttpException('媒体下载失败：HTTP ${response.statusCode}。', uri: uri);
        }
        if (!matchesExpectedContentType(
          response.headers.contentType,
          expectedPrimaryType: widget.kind.name,
        )) {
          throw HttpException(
            '媒体响应类型不符合预期：${response.headers.contentType?.mimeType ?? '未知'}。',
            uri: uri,
          );
        }
        if (response.contentLength > _saveMaxBytes) {
          throw FileSystemException('媒体文件超过保存容量上限。', destination.path);
        }
        consumptionStarted = true;
        final remaining = deadline.remaining();
        final stream = limitByteStream(
          response,
          maxBytes: _saveMaxBytes,
          idleTimeout: deadline.limit(_kSaveNetworkIdleTimeout),
          totalTimeout: remaining,
        );
        await writeByteStreamFileAtomically(
          destination,
          stream,
          maxBytes: _saveMaxBytes,
          idleTimeout: deadline.limit(_kSaveNetworkIdleTimeout),
          totalTimeout: deadline.remaining(),
        );
      } catch (_) {
        if (!consumptionStarted) await cancelByteStream(response);
        rethrow;
      }
    } finally {
      deadline.stop();
      client.close(force: true);
    }
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    if (_copying || _saving) return;
    setState(() => _copying = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      if (widget.kind == MediaPreviewKind.image) {
        final copiedImageData = await _copyImageSource();
        if (!context.mounted) return;
        _showMediaSnack(
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
        _showMediaSnack(
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
        _showMediaSnack(context, message: l10n.mediaPreviewMediaUrlCopied);
        return;
      }
      final bytes = widget.bytes;
      if (bytes != null) {
        final tempPath = await _writeBytesToClipboardTempFile(bytes);
        final ok = await _copyFilePathToClipboard(tempPath);
        if (!context.mounted) return;
        _showMediaSnack(
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
          _showMediaSnack(
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
      _showMediaSnack(
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
      return await fetchBoundedHttpBytes(
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
    await pruneTemporaryFilesBounded(
      dir,
      fileNamePrefix: _kClipboardTempFilePrefix,
      maxRetainedFiles: _kClipboardTempMaxFiles - 1,
      maxAge: _kClipboardTempMaxAge,
      timeout: _kClipboardTempCleanupTimeout,
      onError: _reportMediaTempWriteError,
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

  void _showMediaSnack(
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
    if (_isSvgImage) {
      final placeholder = _imageLoadingBox(context);
      final bytes = widget.bytes;
      if (bytes != null) {
        return SvgPicture.memory(
          bytes,
          width: displaySize.width,
          height: displaySize.height,
          placeholderBuilder: (_) => placeholder,
          errorBuilder: _buildImageError,
        );
      }
      final networkUrl = widget.networkUrl;
      if (networkUrl != null) {
        return SvgPicture.network(
          networkUrl,
          width: displaySize.width,
          height: displaySize.height,
          placeholderBuilder: (_) => placeholder,
          errorBuilder: _buildImageError,
        );
      }
      final filePath = widget.filePath;
      if (filePath != null) {
        return SvgPicture.file(
          File(filePath),
          width: displaySize.width,
          height: displaySize.height,
          placeholderBuilder: (_) => placeholder,
          errorBuilder: _buildImageError,
        );
      }
      return _errorBox(context);
    }
    if (widget.bytes != null) {
      return Image.memory(
        widget.bytes!,
        width: displaySize.width,
        height: displaySize.height,
        fit: BoxFit.contain,
        errorBuilder: _buildImageError,
      );
    }
    if (widget.networkUrl != null) {
      return Image.network(
        widget.networkUrl!,
        width: displaySize.width,
        height: displaySize.height,
        fit: BoxFit.contain,
        errorBuilder: _buildImageError,
      );
    }
    if (widget.filePath != null) {
      return Image.file(
        File(widget.filePath!),
        width: displaySize.width,
        height: displaySize.height,
        fit: BoxFit.contain,
        errorBuilder: _buildImageError,
      );
    }
    return _errorBox(context);
  }

  Widget _buildImageError(
    BuildContext context,
    Object error,
    StackTrace? stack,
  ) {
    if (!_imageErrorLogged) {
      _imageErrorLogged = true;
      silentLog(
        'media_preview_dialog',
        '加载图片预览',
        error,
        stack ?? StackTrace.current,
      );
    }
    return _errorBox(
      context,
      message: openHandLocalizedText(
        context,
        zh: '无法加载此图片。',
        en: 'Unable to load this image.',
      ),
    );
  }

  Widget _imageLoadingBox(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: ColoredBox(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
        child: Center(child: CircularProgressIndicator(color: cs.primary)),
      ),
    );
  }

  Widget _errorBox(BuildContext context, {String? message}) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(kOpenHandRadius12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 48, color: cs.error),
              if (message != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
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
  bool _videoErrorReported = false;

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
      await pruneTemporaryFilesBounded(
        tempDirectory,
        fileNamePrefix: _kPreviewTempFilePrefix,
        maxRetainedFiles: _kPreviewTempMaxFiles - 2,
        maxAge: _kPreviewTempMaxAge,
        timeout: _kPreviewTempCleanupTimeout,
        onError: _reportMediaTempWriteError,
      );
      if (!mounted) return;
      String src;
      if (widget.networkUrl != null) {
        src = widget.networkUrl!;
      } else if (widget.filePath != null) {
        final sourceFile = File(widget.filePath!);
        final sourceStat = await sourceFile.stat().timeout(
          deadline.remaining(),
        );
        if (sourceStat.type != FileSystemEntityType.file) {
          throw FileSystemException('视频源不是普通文件。', sourceFile.path);
        }
        if (sourceStat.size > _kTempMediaMaxBytes) {
          throw const FileSystemException('视频数据超过预览容量上限。');
        }
        final rawExtension = p
            .extension(sourceFile.path)
            .toLowerCase()
            .replaceFirst('.', '');
        final extension = RegExp(r'^[a-z0-9]{1,12}$').hasMatch(rawExtension)
            ? rawExtension
            : _mediaFileExtension(widget.kind, widget.mimeType);
        final mediaFile = _newPreviewTempFile(tempDirectory, extension);
        registerActiveTemporaryFile(mediaFile);
        try {
          await copyFileAtomically(
            sourceFile,
            mediaFile,
            maxBytes: _kTempMediaMaxBytes,
          );
        } catch (_) {
          unregisterActiveTemporaryFile(mediaFile);
          await _deleteTempFile(mediaFile);
          rethrow;
        }
        if (!mounted) {
          unregisterActiveTemporaryFile(mediaFile);
          await _deleteTempFile(mediaFile);
          return;
        }
        _tempMediaPath = mediaFile.path;
        src = Uri.file(mediaFile.path).toString();
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
          registerActiveTemporaryFile(mediaFile);
          try {
            await writeTemporaryFileBytesBounded(
              mediaFile,
              widget.bytes!,
              timeout: deadline.remaining(),
              onSecondaryError: _reportMediaTempWriteError,
            );
          } catch (_) {
            unregisterActiveTemporaryFile(mediaFile);
            rethrow;
          }
          if (!mounted) {
            unregisterActiveTemporaryFile(mediaFile);
            await _deleteTempFile(mediaFile);
            return;
          }
          _tempMediaPath = mediaFile.path;
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
      registerActiveTemporaryFile(htmlFile);
      try {
        await writeTemporaryFileTextBounded(
          htmlFile,
          html,
          timeout: deadline.remaining(),
          onSecondaryError: _reportMediaTempWriteError,
        );
      } catch (_) {
        unregisterActiveTemporaryFile(htmlFile);
        rethrow;
      }
      if (!mounted) {
        unregisterActiveTemporaryFile(htmlFile);
        await _deleteTempFile(htmlFile);
        await _cleanupTempFiles();
        return;
      }
      _tempHtmlPath = htmlFile.path;
      final controller = WebViewController();
      await controller
          .setJavaScriptMode(JavaScriptMode.unrestricted)
          .timeout(deadline.remaining());
      if (!mounted) {
        await _cleanupTempFiles();
        return;
      }
      if (openHandCanSetWebViewBackgroundColor(defaultTargetPlatform)) {
        await controller
            .setBackgroundColor(const Color(0xFF0F0F10))
            .timeout(deadline.remaining());
        if (!mounted) {
          await _cleanupTempFiles();
          return;
        }
      }
      await controller
          .addJavaScriptChannel(
            'OpenHandMediaPreview',
            onMessageReceived: _handleVideoMessage,
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
      unregisterActiveTemporaryFile(File(htmlPath));
    }
    if (mediaPath != null) {
      unregisterActiveTemporaryFile(File(mediaPath));
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

  void _handleVideoMessage(JavaScriptMessage message) {
    if (message.message == 'close') {
      _requestDialogClose();
      return;
    }
    if (message.message != 'error' || _videoErrorReported) return;
    _videoErrorReported = true;
    final error = StateError('视频资源无法解码或不受当前平台支持。');
    silentLog('media_preview_dialog', '加载视频预览', error, StackTrace.current);
    if (!mounted) return;
    setState(
      () => _error = openHandLocalizedText(
        context,
        zh: '无法播放此视频，文件可能已损坏或格式不受支持。',
        en: 'Unable to play this video. The file may be damaged or unsupported.',
      ),
    );
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
  function reportError() { try { window.OpenHandMediaPreview?.postMessage('error'); } catch (_) {} }
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
  media.addEventListener('error', reportError);
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
