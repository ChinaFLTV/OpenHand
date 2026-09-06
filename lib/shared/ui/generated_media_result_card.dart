import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/support/silent_log.dart';
import '../util/bounded_file_io.dart';
import '../util/localized_text.dart';
import 'micro_press_feedback.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'native_audio_preview.dart';
import 'openhand_spacing.dart';
import 'openhand_video_thumbnail.dart';

enum GeneratedMediaResultKind { video, audio }

const double _generatedVideoCardMinWidth = 240;
const double _generatedVideoCardDefaultMaxWidth = 420;

NativeAudioVisualMeta generatedMediaAudioVisualMeta({
  required String title,
  required String detail,
  required String identity,
  String fallbackTitle = 'AI Generated Audio',
}) {
  final cleanTitle = normalizeNativeAudioText(title, fallback: fallbackTitle);
  final cleanDetail = normalizeNativeAudioText(detail, fallback: 'OpenHand');
  final seed = '$cleanTitle|$cleanDetail|$identity'.hashCode & 0x7fffffff;
  final palette =
      _generatedAudioPalettes[seed % _generatedAudioPalettes.length];
  final basename = p.basename(cleanDetail).trim();
  final leaf = normalizeNativeAudioText(
    basename.isEmpty || basename == '/' || basename == '.'
        ? cleanDetail
        : basename,
    fallback: cleanDetail,
  );
  final normalizedLeaf = looksLikeGeneratedNativeAudioName(leaf)
      ? '生成音频'
      : leaf;
  final segments = normalizedLeaf
      .split(RegExp('[-_]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  final artist = segments.length >= 2 && segments.first.length <= 28
      ? segments.first
      : looksLikeGeneratedNativeAudioName(leaf)
      ? 'AI 音频'
      : 'OpenHand 音频';
  final album = looksLikeGeneratedNativeAudioName(leaf)
      ? '生成音频'
      : normalizedLeaf.length <= 32
      ? normalizedLeaf
      : '音频专辑';
  return NativeAudioVisualMeta(
    title: cleanTitle,
    artist: artist,
    album: album,
    detail: cleanDetail,
    primaryColor: palette.$1,
    secondaryColor: palette.$2,
    accentColor: palette.$3,
    coverGlyph: '♪',
    seed: seed,
  );
}

class GeneratedMediaResultCard extends StatefulWidget {
  const GeneratedMediaResultCard({
    super.key,
    required this.kind,
    required this.title,
    required this.detail,
    required this.identity,
    required this.textColor,
    required this.backgroundColor,
    required this.onTap,
    this.videoPath,
    this.videoMimeType,
    this.videoMaxWidth = _generatedVideoCardDefaultMaxWidth,
    this.audioMeta,
  }) : assert(videoMaxWidth > 0);

  final GeneratedMediaResultKind kind;
  final String title;
  final String detail;
  final String identity;
  final Color textColor;
  final Color backgroundColor;
  final VoidCallback onTap;
  final String? videoPath;
  final String? videoMimeType;
  final double videoMaxWidth;
  final NativeAudioVisualMeta? audioMeta;

  @override
  State<GeneratedMediaResultCard> createState() =>
      _GeneratedMediaResultCardState();
}

class _GeneratedMediaResultCardState extends State<GeneratedMediaResultCard>
    with SingleTickerProviderStateMixin {
  static const int _revealCacheLimit = 600;
  static final LinkedHashSet<String> _revealedMediaKeys =
      LinkedHashSet<String>();

  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: kOpenHandMotion420,
  );
  late final Animation<double> _revealAnimation = CurvedAnimation(
    parent: _revealController,
    curve: kOpenHandEntranceCurve,
  );
  String? _videoThumbnailPath;
  bool _videoCaptureRequested = false;
  int _thumbnailRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    _syncRevealAnimation();
    unawaited(_initVideoThumbnail());
  }

  @override
  void didUpdateWidget(covariant GeneratedMediaResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind ||
        oldWidget.identity != widget.identity ||
        oldWidget.title != widget.title) {
      _syncRevealAnimation();
    }
    if (oldWidget.kind != widget.kind ||
        oldWidget.videoPath != widget.videoPath) {
      _thumbnailRequestSerial++;
      _videoThumbnailPath = null;
      _videoCaptureRequested = false;
      unawaited(_initVideoThumbnail());
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  void _syncRevealAnimation() {
    final disableAnimations = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    final revealKey =
        '${widget.kind.name}|${widget.identity.trim()}|${widget.title.trim()}';
    final hasPlayedReveal = _revealedMediaKeys.contains(revealKey);
    if (revealKey.isNotEmpty) {
      _revealedMediaKeys.remove(revealKey);
      _revealedMediaKeys.add(revealKey);
      while (_revealedMediaKeys.length > _revealCacheLimit) {
        _revealedMediaKeys.remove(_revealedMediaKeys.first);
      }
    }
    if (disableAnimations || hasPlayedReveal) {
      _revealController.value = 1;
      return;
    }
    _revealController.forward(from: 0);
  }

  Future<void> _initVideoThumbnail() async {
    final videoPath = widget.videoPath?.trim();
    if (widget.kind != GeneratedMediaResultKind.video ||
        videoPath == null ||
        videoPath.isEmpty) {
      return;
    }
    final serial = ++_thumbnailRequestSerial;
    final cachedPath = OpenHandVideoThumbnailManager.thumbnailPathFor(
      videoPath,
    );
    try {
      if (await isRegularFilePath(cachedPath)) {
        if (!mounted || serial != _thumbnailRequestSerial) return;
        setState(() => _videoThumbnailPath = cachedPath);
        return;
      }
    } catch (error, stack) {
      silentLog('generated_media_card', '检查视频封面缓存失败', error, stack);
    }
    if (!mounted || serial != _thumbnailRequestSerial) return;
    if (OpenHandVideoThumbnailManager.isMarkedFailed(videoPath)) return;
    setState(() => _videoCaptureRequested = true);
  }

  void _handleThumbnailResult(String videoPath, String? thumbnailPath) {
    if (!mounted || widget.videoPath?.trim() != videoPath) return;
    setState(() {
      _videoCaptureRequested = false;
      _videoThumbnailPath = thumbnailPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (widget.kind) {
      GeneratedMediaResultKind.video => _GeneratedVideoResultCard(
        title: widget.title,
        detail: widget.detail,
        textColor: widget.textColor,
        backgroundColor: widget.backgroundColor,
        thumbnailPath: _videoThumbnailPath,
        thumbnailCapture:
            _videoCaptureRequested &&
                widget.videoPath?.trim().isNotEmpty == true
            ? OpenHandVideoThumbnailCapture(
                videoPath: widget.videoPath!.trim(),
                mimeType: widget.videoMimeType?.trim().isNotEmpty == true
                    ? widget.videoMimeType!.trim()
                    : 'video/mp4',
                onResult: (path) =>
                    _handleThumbnailResult(widget.videoPath!.trim(), path),
              )
            : null,
        maxWidth: widget.videoMaxWidth,
        onTap: widget.onTap,
      ),
      GeneratedMediaResultKind.audio => _GeneratedAudioResultCard(
        meta:
            widget.audioMeta ??
            generatedMediaAudioVisualMeta(
              title: widget.title,
              detail: widget.detail,
              identity: widget.identity,
            ),
        title: widget.title,
        textColor: widget.textColor,
        backgroundColor: widget.backgroundColor,
        onTap: widget.onTap,
      ),
    };
    if (openHandReduceMotionOf(context) || _revealController.isCompleted) {
      return child;
    }
    return AnimatedBuilder(
      animation: _revealAnimation,
      child: child,
      builder: (context, child) {
        final raw = _revealAnimation.value;
        final progress = raw.clamp(0.0, 1.0);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * 10),
            child: Transform.scale(
              alignment: Alignment.centerLeft,
              scale: 0.965 + 0.035 * raw,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _GeneratedVideoResultCard extends StatelessWidget {
  const _GeneratedVideoResultCard({
    required this.title,
    required this.detail,
    required this.textColor,
    required this.backgroundColor,
    required this.onTap,
    this.thumbnailPath,
    this.thumbnailCapture,
    required this.maxWidth,
  });

  final String title;
  final String detail;
  final Color textColor;
  final Color backgroundColor;
  final VoidCallback onTap;
  final String? thumbnailPath;
  final Widget? thumbnailCapture;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = Color.alphaBlend(
      textColor.withValues(alpha: 0.08),
      backgroundColor,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: openHandLocalizedText(
          context,
          zh: '打开视频预览：$title',
          en: 'Open video preview: $title',
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: kOpenHandBorderRadius14,
            onTap: onTap,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                minWidth: maxWidth < _generatedVideoCardMinWidth
                    ? maxWidth
                    : _generatedVideoCardMinWidth,
              ),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: kOpenHandBorderRadius14,
                border: Border.all(color: textColor.withValues(alpha: 0.16)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumbnailPath != null)
                          Image.file(
                            File(thumbnailPath!),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            cacheWidth: 840,
                            errorBuilder: (_, _, _) =>
                                Container(color: Colors.black87),
                          )
                        else
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.black.withValues(alpha: 0.78),
                                  Colors.black.withValues(alpha: 0.92),
                                ],
                              ),
                            ),
                          ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0),
                                Colors.black.withValues(alpha: 0.35),
                              ],
                            ),
                          ),
                        ),
                        Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.85),
                                width: 1.4,
                              ),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: kOpenHandBorderRadius6,
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.videocam_outlined,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                kOpenHandHGap4,
                                Text(
                                  'VIDEO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (thumbnailCapture != null)
                          Positioned(left: 0, top: 0, child: thumbnailCapture!),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        kOpenHandGap2,
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: textColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const List<(Color, Color, Color)> _generatedAudioPalettes =
    <(Color, Color, Color)>[
      (Color(0xFF65734F), Color(0xFF96A878), Color(0xFFE5EBD7)),
      (Color(0xFF4F6B70), Color(0xFF7FA3A1), Color(0xFFE0ECEA)),
      (Color(0xFF536D82), Color(0xFF89A7B8), Color(0xFFE2ECF1)),
      (Color(0xFF6A7258), Color(0xFFA8B086), Color(0xFFECE9D6)),
      (Color(0xFF51705F), Color(0xFF84A783), Color(0xFFE3EEE6)),
    ];

const double _generatedAudioCardMinWidth = 260;
const double _generatedAudioCardMaxWidth = 360;
const double _generatedAudioCardRadius = 18;
const double _generatedAudioBannerAspectRatio = 16 / 9;
const double _generatedAudioCoverSize = 74;
const double _generatedAudioPlayButtonSize = 38;
const double _generatedAudioHoverLift = 2;
const double _generatedAudioCardBorderWidth = 1.2;

class _GeneratedAudioCardStyle {
  const _GeneratedAudioCardStyle({
    required this.surface,
    required this.border,
    required this.borderHover,
    required this.bannerStart,
    required this.bannerMid,
    required this.bannerEnd,
    required this.bannerStroke,
    required this.bannerPattern,
    required this.coverForeground,
    required this.playBackground,
    required this.playBorder,
    required this.playIcon,
    required this.titleColor,
    required this.subtitleColor,
    required this.metaIconColor,
  });

  factory _GeneratedAudioCardStyle.resolve({
    required ThemeData theme,
    required NativeAudioVisualMeta meta,
    required Color bubbleBackground,
    required Color bubbleTextColor,
  }) {
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final quietSurface = Color.alphaBlend(
      colors.primary.withValues(alpha: isDark ? 0.07 : 0.035),
      colors.surfaceContainerHighest,
    );
    final surface = Color.alphaBlend(
      bubbleTextColor.withValues(alpha: isDark ? 0.025 : 0.014),
      Color.alphaBlend(
        bubbleBackground.withValues(alpha: isDark ? 0.08 : 0.12),
        quietSurface,
      ),
    );
    return _GeneratedAudioCardStyle(
      surface: surface,
      border: colors.outlineVariant.withValues(alpha: isDark ? 0.36 : 0.62),
      borderHover: colors.primary.withValues(alpha: isDark ? 0.54 : 0.42),
      bannerStart: Color.alphaBlend(
        meta.primaryColor.withValues(alpha: isDark ? 0.18 : 0.12),
        colors.surfaceContainerHighest,
      ),
      bannerMid: Color.alphaBlend(
        meta.accentColor.withValues(alpha: isDark ? 0.13 : 0.10),
        colors.surfaceContainerHigh,
      ),
      bannerEnd: Color.alphaBlend(
        colors.primary.withValues(alpha: isDark ? 0.08 : 0.045),
        colors.surfaceContainerHigh,
      ),
      bannerStroke: colors.outlineVariant.withValues(
        alpha: isDark ? 0.38 : 0.55,
      ),
      bannerPattern: colors.onSurfaceVariant.withValues(
        alpha: isDark ? 0.16 : 0.20,
      ),
      coverForeground: colors.onSurface.withValues(alpha: 0.94),
      playBackground: colors.surface.withValues(alpha: isDark ? 0.56 : 0.62),
      playBorder: colors.outlineVariant.withValues(alpha: isDark ? 0.58 : 0.72),
      playIcon: colors.primary,
      titleColor: colors.onSurface,
      subtitleColor: colors.onSurfaceVariant,
      metaIconColor: colors.primary.withValues(alpha: isDark ? 0.86 : 0.78),
    );
  }

  final Color surface;
  final Color border;
  final Color borderHover;
  final Color bannerStart;
  final Color bannerMid;
  final Color bannerEnd;
  final Color bannerStroke;
  final Color bannerPattern;
  final Color coverForeground;
  final Color playBackground;
  final Color playBorder;
  final Color playIcon;
  final Color titleColor;
  final Color subtitleColor;
  final Color metaIconColor;

  Color borderFor(double progress) =>
      Color.lerp(border, borderHover, progress) ?? border;
}

class _GeneratedAudioResultCard extends StatefulWidget {
  const _GeneratedAudioResultCard({
    required this.meta,
    required this.title,
    required this.textColor,
    required this.backgroundColor,
    required this.onTap,
  });

  final NativeAudioVisualMeta meta;
  final String title;
  final Color textColor;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  State<_GeneratedAudioResultCard> createState() =>
      _GeneratedAudioResultCardState();
}

class _GeneratedAudioResultCardState extends State<_GeneratedAudioResultCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hoverController = AnimationController(
    vsync: this,
    duration: kOpenHandMotion180,
  );
  bool _hovered = false;

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  void _onHoverChanged(bool hovered) {
    if (_hovered == hovered) return;
    _hovered = hovered;
    if (hovered) {
      _hoverController.forward();
    } else {
      _hoverController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final disableAnimations = openHandReduceMotionOf(context);
    final style = _GeneratedAudioCardStyle.resolve(
      theme: Theme.of(context),
      meta: meta,
      bubbleBackground: widget.backgroundColor,
      bubbleTextColor: widget.textColor,
    );
    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: disableAnimations ? null : (_) => _onHoverChanged(true),
        onExit: disableAnimations ? null : (_) => _onHoverChanged(false),
        child: Semantics(
          button: true,
          label: openHandLocalizedText(
            context,
            zh: '打开音频预览：${widget.title}',
            en: 'Open audio preview: ${widget.title}',
          ),
          child: AnimatedBuilder(
            animation: _hoverController,
            builder: (context, _) {
              final progress = disableAnimations ? 0.0 : _hoverController.value;
              final radius = BorderRadius.circular(_generatedAudioCardRadius);
              final hoverInset = disableAnimations
                  ? 0.0
                  : _generatedAudioHoverLift;
              return Padding(
                padding: EdgeInsets.only(top: hoverInset),
                child: Transform.translate(
                  offset: Offset(0, -hoverInset * progress),
                  child: MicroPressFeedback(
                    scale: 0.985,
                    child: GestureDetector(
                      onTap: widget.onTap,
                      child: Container(
                        constraints: const BoxConstraints(
                          maxWidth: _generatedAudioCardMaxWidth,
                          minWidth: _generatedAudioCardMinWidth,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          color: style.surface,
                        ),
                        foregroundDecoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(
                            color: style.borderFor(progress),
                            width: _generatedAudioCardBorderWidth,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: radius,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildCoverBanner(meta, style),
                              _buildInfoRow(context, meta, style),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCoverBanner(
    NativeAudioVisualMeta meta,
    _GeneratedAudioCardStyle style,
  ) {
    return AspectRatio(
      aspectRatio: _generatedAudioBannerAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [style.bannerStart, style.bannerMid, style.bannerEnd],
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: style.bannerStroke)),
              ),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 16,
            child: Icon(
              Icons.graphic_eq_rounded,
              size: 34,
              color: style.bannerPattern,
            ),
          ),
          Positioned(
            right: -18,
            bottom: -24,
            child: Icon(
              Icons.album_rounded,
              size: 108,
              color: style.bannerPattern.withValues(alpha: 0.70),
            ),
          ),
          Center(
            child: _GeneratedAudioAlbumCover(
              meta: meta,
              size: _generatedAudioCoverSize,
              foregroundColor: style.coverForeground,
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: _generatedAudioPlayButtonSize,
              height: _generatedAudioPlayButtonSize,
              decoration: BoxDecoration(
                color: style.playBackground,
                shape: BoxShape.circle,
                border: Border.all(color: style.playBorder),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: style.playIcon,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    NativeAudioVisualMeta meta,
    _GeneratedAudioCardStyle style,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            meta.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: style.titleColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          kOpenHandGap4,
          Row(
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 14,
                color: style.metaIconColor,
              ),
              kOpenHandHGap5,
              Expanded(
                child: Text(
                  '${meta.artist} · ${meta.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: style.subtitleColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeneratedAudioAlbumCover extends StatelessWidget {
  const _GeneratedAudioAlbumCover({
    required this.meta,
    required this.size,
    required this.foregroundColor,
  });

  final NativeAudioVisualMeta meta;
  final double size;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.58),
            ),
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  meta.primaryColor.withValues(alpha: 0.12),
                  colors.surfaceContainerHighest,
                ),
                Color.alphaBlend(
                  meta.accentColor.withValues(alpha: 0.10),
                  colors.surfaceContainerHighest,
                ),
                Color.alphaBlend(
                  colors.primary.withValues(alpha: 0.045),
                  colors.surfaceContainerHigh,
                ),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -size * 0.16,
                bottom: -size * 0.22,
                child: Icon(
                  Icons.album_rounded,
                  size: size * 0.86,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.16),
                ),
              ),
              Positioned(
                left: size * 0.10,
                bottom: size * 0.10,
                child: Icon(
                  Icons.graphic_eq_rounded,
                  size: size * 0.18,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.38),
                ),
              ),
              Center(
                child: Container(
                  width: size * 0.30,
                  height: size * 0.30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surface.withValues(alpha: 0.40),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.68),
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  meta.coverGlyph,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.w900,
                    fontSize: size * 0.38,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
