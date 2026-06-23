import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/support/silent_log.dart';
import '../util/localized_text.dart';

const Duration kNativeAudioLoadTimeout = Duration(seconds: 18);
const Duration kNativeAudioControlTimeout = Duration(seconds: 8);
const Duration kNativeAudioSeekStep = Duration(seconds: 15);
const Curve kNativeAudioMotionCurve = Cubic(0.22, 1.22, 0.36, 1);
const double _kNativeAudioWideBreakpoint = 760;
const double _kNativeAudioShortBreakpoint = 430;

class NativeAudioPreviewController {
  _NativeAudioPreviewState? _state;

  Future<void> togglePlayPause() async {
    await _state?._togglePlayPause();
  }
}

class NativeAudioPreviewSource {
  const NativeAudioPreviewSource._({
    this.bytes,
    this.networkUrl,
    this.filePath,
    this.mimeType,
    this.detail,
  });

  factory NativeAudioPreviewSource.bytes({
    required Uint8List bytes,
    String? mimeType,
    String? detail,
  }) => NativeAudioPreviewSource._(
    bytes: bytes,
    mimeType: mimeType,
    detail: detail,
  );

  factory NativeAudioPreviewSource.network({
    required String url,
    String? mimeType,
    String? detail,
  }) => NativeAudioPreviewSource._(
    networkUrl: url,
    mimeType: mimeType,
    detail: detail ?? url,
  );

  factory NativeAudioPreviewSource.file({
    required String filePath,
    String? mimeType,
    String? detail,
  }) => NativeAudioPreviewSource._(
    filePath: filePath,
    mimeType: mimeType,
    detail: detail ?? filePath,
  );

  final Uint8List? bytes;
  final String? networkUrl;
  final String? filePath;
  final String? mimeType;
  final String? detail;
}

class NativeAudioVisualMeta {
  const NativeAudioVisualMeta({
    required this.title,
    required this.artist,
    required this.album,
    required this.detail,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.coverGlyph,
    required this.lyricLines,
    required this.seed,
  });

  factory NativeAudioVisualMeta.fromText({
    required String title,
    required String detail,
    String fallbackTitle = 'Audio',
    String fallbackDetail = 'OpenHand',
  }) {
    final cleanTitle = normalizeNativeAudioText(title, fallback: fallbackTitle);
    final cleanDetail = normalizeNativeAudioText(
      detail,
      fallback: fallbackDetail,
    );
    final seed = '$cleanTitle|$cleanDetail'.hashCode & 0x7fffffff;
    final palette = _kNativeAudioPalettes[seed % _kNativeAudioPalettes.length];
    return NativeAudioVisualMeta(
      title: cleanTitle,
      artist: deriveNativeAudioArtist(cleanDetail),
      album: deriveNativeAudioAlbum(cleanDetail),
      detail: cleanDetail,
      primaryColor: palette.$1,
      secondaryColor: palette.$2,
      accentColor: palette.$3,
      coverGlyph: '♪',
      lyricLines: deriveNativeAudioLyrics(cleanTitle, cleanDetail),
      seed: seed,
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
  final int seed;
}

class NativeAudioPreview extends StatefulWidget {
  const NativeAudioPreview({
    super.key,
    required this.title,
    required this.source,
    required this.meta,
    this.controller,
    this.onOpenExternal,
    this.autoplay = false,
    this.motionDuration = const Duration(milliseconds: 280),
    this.motionCurve = kNativeAudioMotionCurve,
  });

  final String title;
  final NativeAudioPreviewSource source;
  final NativeAudioVisualMeta meta;
  final NativeAudioPreviewController? controller;
  final VoidCallback? onOpenExternal;
  final bool autoplay;
  final Duration motionDuration;
  final Curve motionCurve;

  @override
  State<NativeAudioPreview> createState() => _NativeAudioPreviewState();
}

enum _NativeAudioPlayMode { sequence, repeatOne, shuffle }

enum _NativeAudioEffect {
  standard('标准', 'Standard', Icons.tune_rounded, 1.0),
  spatial('3D', '3D', Icons.view_in_ar_rounded, 1.0),
  vocal('人声', 'Vocal', Icons.record_voice_over_rounded, 1.0),
  warm('暖声', 'Warm', Icons.graphic_eq_rounded, 0.96);

  const _NativeAudioEffect(
    this.zhLabel,
    this.enLabel,
    this.icon,
    this.volumeScale,
  );

  final String zhLabel;
  final String enLabel;
  final IconData icon;
  final double volumeScale;
}

class _NativeAudioPreviewState extends State<NativeAudioPreview> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  _NativeAudioPlayMode _playMode = _NativeAudioPlayMode.sequence;
  _NativeAudioEffect _effect = _NativeAudioEffect.standard;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;
  double _volume = 0.86;
  bool _muted = false;
  bool _loading = true;
  bool _sourceReady = false;
  bool _disposed = false;
  bool _operationInFlight = false;
  bool _seeking = false;
  String? _loadError;
  String? _tempAudioPath;
  int _bootstrapSerial = 0;

  bool get _isPlaying => _playerState == PlayerState.playing;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _subscriptions
      ..add(
        _player.onPlayerStateChanged.listen((state) {
          if (!mounted) return;
          setState(() => _playerState = state);
        }),
      )
      ..add(
        _player.onDurationChanged.listen((duration) {
          if (!mounted || duration < Duration.zero) return;
          setState(() => _duration = duration);
        }),
      )
      ..add(
        _player.onPositionChanged.listen((position) {
          if (!mounted || _seeking || position < Duration.zero) return;
          setState(() => _position = _clampDuration(position, _duration));
        }),
      )
      ..add(
        _player.onPlayerComplete.listen((_) {
          if (!mounted) return;
          unawaited(_handleComplete());
        }),
      );
    unawaited(_bootstrap());
  }

  @override
  void didUpdateWidget(covariant NativeAudioPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      final oldController = oldWidget.controller;
      if (oldController?._state == this) oldController!._state = null;
      widget.controller?._state = this;
    }
    if (!_sameSource(oldWidget.source, widget.source)) {
      unawaited(_bootstrap());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (widget.controller?._state == this) widget.controller?._state = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_disposePlayerAndTemp());
    super.dispose();
  }

  bool _sameSource(NativeAudioPreviewSource a, NativeAudioPreviewSource b) {
    return identical(a.bytes, b.bytes) &&
        a.networkUrl == b.networkUrl &&
        a.filePath == b.filePath &&
        a.mimeType == b.mimeType;
  }

  Future<void> _bootstrap() async {
    if (_disposed) return;
    final serial = ++_bootstrapSerial;
    setState(() {
      _loading = true;
      _sourceReady = false;
      _loadError = null;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    try {
      await _stopForSourceReset();
      await _deleteTempAudioFile();
      await _player
          .setReleaseMode(ReleaseMode.stop)
          .timeout(kNativeAudioControlTimeout);
      await _player
          .setVolume(_effectiveVolume)
          .timeout(kNativeAudioControlTimeout);
      final source = await _buildAudioSource();
      await _player.setSource(source).timeout(kNativeAudioLoadTimeout);
      final duration = await _resolveDuration();
      if (_disposed || !mounted || serial != _bootstrapSerial) return;
      setState(() {
        _duration = duration;
        _loading = false;
        _sourceReady = true;
        _loadError = null;
      });
      if (widget.autoplay) {
        await _play().timeout(kNativeAudioControlTimeout);
      }
    } on TimeoutException catch (error, stack) {
      _handleLoadFailure(error, stack, serial);
    } catch (error, stack) {
      _handleLoadFailure(error, stack, serial);
    }
  }

  Future<Duration> _resolveDuration() async {
    final initial = await _player.getDuration().timeout(
      kNativeAudioControlTimeout,
      onTimeout: () => null,
    );
    if (initial != null && initial > Duration.zero) return initial;
    for (var attempt = 0; attempt < 6; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final next = await _player.getDuration().timeout(
        kNativeAudioControlTimeout,
        onTimeout: () => null,
      );
      if (next != null && next > Duration.zero) return next;
    }
    return Duration.zero;
  }

  Future<Source> _buildAudioSource() async {
    final mimeType = widget.source.mimeType;
    final filePath = widget.source.filePath;
    if (filePath != null && filePath.trim().isNotEmpty) {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw FileSystemException('Audio source file is missing.', filePath);
      }
      return DeviceFileSource(filePath, mimeType: mimeType);
    }
    final url = widget.source.networkUrl;
    if (url != null && url.trim().isNotEmpty) {
      final uri = Uri.tryParse(url.trim());
      final scheme = uri?.scheme.toLowerCase();
      if (uri == null ||
          (scheme != 'http' && scheme != 'https' && scheme != 'file')) {
        throw FormatException('Unsupported audio URL: $url');
      }
      if (scheme == 'file') {
        return DeviceFileSource(uri.toFilePath(), mimeType: mimeType);
      }
      return UrlSource(url.trim(), mimeType: mimeType);
    }
    final bytes = widget.source.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      if (!kIsWeb) {
        final ext = _extensionForAudioMime(widget.source.mimeType);
        final file = File(
          '${Directory.systemTemp.path}/openhand-audio-${DateTime.now().microsecondsSinceEpoch}.$ext',
        );
        await file
            .writeAsBytes(bytes, flush: true)
            .timeout(kNativeAudioControlTimeout);
        _tempAudioPath = file.path;
        return DeviceFileSource(file.path, mimeType: mimeType);
      }
      return BytesSource(bytes, mimeType: mimeType);
    }
    throw const FileSystemException('Audio source is unavailable.');
  }

  void _handleLoadFailure(Object error, StackTrace stack, int serial) {
    silentLog('native_audio_preview', 'load source failed', error, stack);
    if (_disposed || !mounted || serial != _bootstrapSerial) return;
    setState(() {
      _loading = false;
      _sourceReady = false;
      _loadError = openHandLocalizedText(
        context,
        zh: '音频载入失败，可使用系统播放器打开。',
        en: 'Unable to load audio. Open with the system player instead.',
      );
    });
  }

  Future<void> _handleComplete() async {
    switch (_playMode) {
      case _NativeAudioPlayMode.repeatOne:
        await _seekTo(Duration.zero);
        await _play();
      case _NativeAudioPlayMode.shuffle:
        final dur = _duration;
        final maxMs = math.max(0, dur.inMilliseconds - 1000);
        final offset = maxMs > 0 ? math.Random().nextInt(maxMs) : 0;
        await _seekTo(Duration(milliseconds: offset));
        await _play();
      case _NativeAudioPlayMode.sequence:
        await _seekTo(Duration.zero);
        if (mounted) setState(() => _playerState = PlayerState.completed);
    }
  }

  Future<void> _togglePlayPause() async {
    if (_operationInFlight) return;
    if (!_sourceReady) {
      if (_loadError != null) unawaited(_bootstrap());
      return;
    }
    _operationInFlight = true;
    try {
      if (_isPlaying) {
        await _player.pause().timeout(kNativeAudioControlTimeout);
      } else {
        await _play().timeout(kNativeAudioControlTimeout);
      }
    } catch (error, stack) {
      silentLog('native_audio_preview', 'toggle playback failed', error, stack);
      if (mounted) {
        setState(() {
          _loadError = openHandLocalizedText(
            context,
            zh: '播放失败，请重试或使用系统播放器。',
            en: 'Playback failed. Try again or open with the system player.',
          );
        });
      }
    } finally {
      _operationInFlight = false;
    }
  }

  Future<void> _play() async {
    if (!_sourceReady) return;
    if (_playerState == PlayerState.completed) {
      await _seekTo(Duration.zero);
    }
    await _applyEffectToPlayer();
    await _player.resume();
  }

  Future<void> _seekBy(Duration delta) async {
    await _seekTo(_position + delta);
  }

  Future<void> _seekTo(Duration target) async {
    if (!_sourceReady) return;
    final clamped = _clampDuration(target, _duration);
    setState(() {
      _seeking = true;
      _position = clamped;
    });
    try {
      await _player.seek(clamped).timeout(kNativeAudioControlTimeout);
    } catch (error, stack) {
      silentLog('native_audio_preview', 'seek failed', error, stack);
    } finally {
      if (mounted) setState(() => _seeking = false);
    }
  }

  Future<void> _setVolume(double value) async {
    final next = value.clamp(0.0, 1.0);
    setState(() {
      _volume = next;
      _muted = next <= 0;
    });
    try {
      await _player
          .setVolume(_effectiveVolume)
          .timeout(kNativeAudioControlTimeout);
    } catch (error, stack) {
      silentLog('native_audio_preview', 'set volume failed', error, stack);
    }
  }

  Future<void> _toggleMuted() async {
    setState(() {
      _muted = !_muted;
      if (!_muted && _volume <= 0) _volume = 0.6;
    });
    try {
      await _player
          .setVolume(_effectiveVolume)
          .timeout(kNativeAudioControlTimeout);
    } catch (error, stack) {
      silentLog('native_audio_preview', 'toggle mute failed', error, stack);
    }
  }

  Future<void> _setEffect(_NativeAudioEffect effect) async {
    setState(() => _effect = effect);
    try {
      await _applyEffectToPlayer().timeout(kNativeAudioControlTimeout);
    } catch (error, stack) {
      silentLog('native_audio_preview', 'apply effect failed', error, stack);
    }
  }

  Future<void> _applyEffectToPlayer() async {
    try {
      await _player
          .setVolume(_effectiveVolume)
          .timeout(kNativeAudioControlTimeout);
    } catch (error, stack) {
      silentLog(
        'native_audio_preview',
        'set effect volume failed',
        error,
        stack,
      );
    }
  }

  double get _effectiveVolume =>
      _muted ? 0.0 : (_volume * _effect.volumeScale).clamp(0.0, 1.0);

  void _cyclePlayMode() {
    setState(() {
      _playMode = switch (_playMode) {
        _NativeAudioPlayMode.sequence => _NativeAudioPlayMode.repeatOne,
        _NativeAudioPlayMode.repeatOne => _NativeAudioPlayMode.shuffle,
        _NativeAudioPlayMode.shuffle => _NativeAudioPlayMode.sequence,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final colorScheme = Theme.of(context).colorScheme;
    final motionDur = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : widget.motionDuration;
    final baseColor = colorScheme.surface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackSize = MediaQuery.sizeOf(context);
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackSize.width;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallbackSize.height;
        final useWide = width >= _kNativeAudioWideBreakpoint &&
            height >= _kNativeAudioShortBreakpoint;
        final hPad = useWide ? 32.0 : 20.0;
        final vPad = useWide ? 22.0 : 18.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                baseColor,
                Color.lerp(
                      baseColor,
                      meta.primaryColor,
                      colorScheme.brightness == Brightness.dark ? 0.14 : 0.08,
                    ) ??
                    baseColor,
                Color.lerp(
                      baseColor,
                      meta.secondaryColor,
                      colorScheme.brightness == Brightness.dark ? 0.10 : 0.06,
                    ) ??
                    baseColor,
              ],
            ),
          ),
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _NativeAudioAnimatedBackdrop(
                    meta: meta,
                    duration: motionDur,
                    curve: widget.motionCurve,
                    isDark: colorScheme.brightness == Brightness.dark,
                  ),
                ),
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: motionDur,
                    switchInCurve: widget.motionCurve,
                    switchOutCurve: Curves.easeOutCubic,
                    child: Padding(
                      key: ValueKey<bool>(useWide),
                      padding: EdgeInsets.symmetric(
                        horizontal: hPad,
                        vertical: vPad,
                      ),
                      child: useWide
                          ? _buildWide(context)
                          : _buildCompact(context),
                    ),
                  ),
                ),
                if (_loading)
                  Positioned.fill(
                    child: ColoredBox(
                      color: colorScheme.surface.withValues(alpha: 0.60),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: colorScheme.primary,
                          strokeWidth: 2.6,
                        ),
                      ),
                    ),
                  ),
                if (_loadError != null)
                  Positioned.fill(child: _buildError(context)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWide(BuildContext context) {
    final hasLyrics = widget.meta.lyricLines.isNotEmpty;
    return Row(
      children: [
        Expanded(
          flex: hasLyrics ? 90 : 1,
          child: _buildAlbumColumn(context, compact: false),
        ),
        if (hasLyrics) ...[
          const SizedBox(width: 32),
          Expanded(flex: 110, child: _buildLyricsColumn(context)),
        ],
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    final hasLyrics = widget.meta.lyricLines.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < 420;
        return Column(
          children: [
            Expanded(child: _buildAlbumColumn(context, compact: true)),
            if (hasLyrics && !short) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: math.min(110, constraints.maxHeight * 0.26),
                child: _buildLyricsColumn(context, compact: true),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAlbumColumn(BuildContext context, {required bool compact}) {
    final meta = widget.meta;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallback = MediaQuery.sizeOf(context);
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : fallback.width;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallback.height;
        final short = height < 500;
        final coverLimit = compact ? 144.0 : (short ? 210.0 : 240.0);
        final squareSize = math.min(width, height * 0.54);
        final coverSize = math
            .min(coverLimit, squareSize)
            .clamp(compact ? 80.0 : 148.0, coverLimit)
            .toDouble();
        final gap = compact || short ? 10.0 : 14.0;
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              child: _NativeAudioAlbumCover(
                meta: meta,
                size: coverSize,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                isPlaying: _isPlaying,
                motionDuration: widget.motionDuration,
                motionCurve: widget.motionCurve,
              ),
            ),
            SizedBox(height: gap),
            _buildTrackMeta(context, compact: compact || short),
            SizedBox(height: gap),
            _buildProgress(context),
            SizedBox(height: gap),
            _buildTransportRow(context),
            SizedBox(height: gap * 0.8),
            _buildControlsBar(context),
          ],
        );
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: Center(child: content),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackMeta(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final meta = widget.meta;
    final showAlbum = meta.album.trim().isNotEmpty &&
        meta.album.trim().toLowerCase() != meta.title.trim().toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showAlbum) ...[
          Text(
            meta.album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 3),
        ],
        Text(
          meta.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            fontSize: compact ? 17 : 21,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          meta.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: cs.primary,
            inactiveTrackColor: cs.outlineVariant,
            thumbColor: cs.primary,
            overlayColor: cs.primary.withValues(alpha: 0.12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: progress,
            onChanged: _sourceReady
                ? (value) {
                    final target = Duration(
                      milliseconds:
                          (_duration.inMilliseconds * value).round(),
                    );
                    setState(() => _position = target);
                  }
                : null,
            onChangeEnd: _sourceReady
                ? (value) {
                    final target = Duration(
                      milliseconds:
                          (_duration.inMilliseconds * value).round(),
                    );
                    unawaited(_seekTo(target));
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _NativeAudioTimeText(_formatNativeAudioTime(_position)),
              _NativeAudioTimeText(_formatNativeAudioTime(_duration)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransportRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _NativeAudioIconButton(
          tooltip: openHandLocalizedText(
            context,
            zh: '后退 15 秒',
            en: 'Back 15 s',
          ),
          icon: Icons.replay_10_rounded,
          onPressed:
              _sourceReady ? () => unawaited(_seekBy(-kNativeAudioSeekStep)) : null,
        ),
        const SizedBox(width: 12),
        _NativeAudioIconButton(
          tooltip: openHandLocalizedText(
            context,
            zh: _isPlaying ? '暂停' : '播放',
            en: _isPlaying ? 'Pause' : 'Play',
          ),
          icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          prominent: true,
          onPressed:
              _sourceReady ? () => unawaited(_togglePlayPause()) : null,
        ),
        const SizedBox(width: 12),
        _NativeAudioIconButton(
          tooltip: openHandLocalizedText(
            context,
            zh: '快进 15 秒',
            en: 'Forward 15 s',
          ),
          icon: Icons.forward_10_rounded,
          onPressed:
              _sourceReady ? () => unawaited(_seekBy(kNativeAudioSeekStep)) : null,
        ),
      ],
    );
  }

  // 底部控制栏：播放模式 | 音量 | 音效
  Widget _buildControlsBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        // 播放模式按钮
        _NativeAudioIconButton(
          tooltip: _playModeTooltip(context),
          icon: _playModeIcon,
          active: _playMode != _NativeAudioPlayMode.sequence,
          compact: true,
          onPressed: _cyclePlayMode,
        ),
        const SizedBox(width: 2),
        // 音量静音按钮
        _NativeAudioIconButton(
          tooltip: openHandLocalizedText(
            context,
            zh: _muted ? '取消静音' : '静音',
            en: _muted ? 'Unmute' : 'Mute',
          ),
          icon: _muted || _volume <= 0
              ? Icons.volume_off_rounded
              : (_volume < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded),
          compact: true,
          onPressed: () => unawaited(_toggleMuted()),
        ),
        // 音量滑条
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.outlineVariant,
              thumbColor: cs.primary,
              overlayColor: cs.primary.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
            ),
            child: Slider(
              value: _muted ? 0.0 : _volume,
              onChanged: (value) => unawaited(_setVolume(value)),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // 音效按钮（单按钮弹出菜单）
        _NativeAudioEffectMenuButton(
          effect: _effect,
          onSelect: (effect) => unawaited(_setEffect(effect)),
          context: context,
        ),
      ],
    );
  }

  Widget _buildLyricsColumn(BuildContext context, {bool compact = false}) {
    final cs = Theme.of(context).colorScheme;
    final lines = widget.meta.lyricLines;
    final active = _activeLyricIndex(lines.length);
    final title = openHandLocalizedText(context, zh: '歌词', en: 'Lyrics');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.70),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        SizedBox(height: compact ? 6 : 12),
        Expanded(
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0, 0.14, 0.86, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(vertical: compact ? 4 : 10),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final selected = index == active;
                return AnimatedScale(
                  duration: widget.motionDuration,
                  curve: widget.motionCurve,
                  scale: selected ? 1.0 : 0.96,
                  alignment: Alignment.centerLeft,
                  child: AnimatedDefaultTextStyle(
                    duration: widget.motionDuration,
                    curve: widget.motionCurve,
                    style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                      color: selected
                          ? cs.onSurface
                          : cs.onSurfaceVariant.withValues(alpha: 0.50),
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0,
                      fontSize: compact ? 14 : 19,
                      height: 1.22,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: compact ? 3 : 6,
                      ),
                      child: Text(
                        lines[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface.withValues(alpha: 0.76),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: cs.error,
                    size: 30,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => unawaited(_bootstrap()),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          openHandLocalizedText(
                            context,
                            zh: '重试',
                            en: 'Retry',
                          ),
                        ),
                      ),
                      if (widget.onOpenExternal != null)
                        FilledButton.icon(
                          onPressed: widget.onOpenExternal,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: Text(
                            openHandLocalizedText(
                              context,
                              zh: '系统播放器',
                              en: 'System Player',
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _activeLyricIndex(int lineCount) {
    if (lineCount <= 1) return 0;
    final durationMs = _duration.inMilliseconds;
    final positionMs = _position.inMilliseconds;
    final ratio = durationMs > 0
        ? positionMs / durationMs
        : ((positionMs % (lineCount * 6000)) / (lineCount * 6000));
    return (ratio * lineCount).floor().clamp(0, lineCount - 1);
  }

  String _playModeTooltip(BuildContext context) {
    return switch (_playMode) {
      _NativeAudioPlayMode.sequence => openHandLocalizedText(
        context,
        zh: '顺序播放',
        en: 'Sequence playback',
      ),
      _NativeAudioPlayMode.repeatOne => openHandLocalizedText(
        context,
        zh: '单曲循环',
        en: 'Repeat one',
      ),
      _NativeAudioPlayMode.shuffle => openHandLocalizedText(
        context,
        zh: '随机播放',
        en: 'Shuffle playback',
      ),
    };
  }

  IconData get _playModeIcon {
    return switch (_playMode) {
      _NativeAudioPlayMode.sequence => Icons.playlist_play_rounded,
      _NativeAudioPlayMode.repeatOne => Icons.repeat_one_rounded,
      _NativeAudioPlayMode.shuffle => Icons.shuffle_rounded,
    };
  }

  Future<void> _deleteTempAudioFile() async {
    final path = _tempAudioPath;
    _tempAudioPath = null;
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error, stack) {
      silentLog(
        'native_audio_preview',
        'delete temp audio failed',
        error,
        stack,
      );
    }
  }

  Future<void> _stopForSourceReset() async {
    try {
      await _player.stop().timeout(kNativeAudioControlTimeout);
    } catch (error, stack) {
      silentLog(
        'native_audio_preview',
        'stop before reset failed',
        error,
        stack,
      );
    }
  }

  Future<void> _disposePlayerAndTemp() async {
    try {
      await _player.dispose().timeout(kNativeAudioControlTimeout);
    } catch (error, stack) {
      silentLog('native_audio_preview', 'dispose player failed', error, stack);
    } finally {
      await _deleteTempAudioFile();
    }
  }
}

class _NativeAudioAlbumCover extends StatefulWidget {
  const _NativeAudioAlbumCover({
    required this.meta,
    required this.size,
    required this.foregroundColor,
    required this.isPlaying,
    required this.motionDuration,
    required this.motionCurve,
  });

  final NativeAudioVisualMeta meta;
  final double size;
  final Color foregroundColor;
  final bool isPlaying;
  final Duration motionDuration;
  final Curve motionCurve;

  @override
  State<_NativeAudioAlbumCover> createState() => _NativeAudioAlbumCoverState();
}

class _NativeAudioAlbumCoverState extends State<_NativeAudioAlbumCover>
    with TickerProviderStateMixin {
  late final AnimationController _rotateController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) {
      _rotateController.repeat();
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _NativeAudioAlbumCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_rotateController.isAnimating) {
      _rotateController.repeat();
      _glowController.repeat(reverse: true);
    } else if (!widget.isPlaying && _rotateController.isAnimating) {
      _rotateController.stop();
      _glowController.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotateController.stop();
      _glowController.stop();
    } else if (widget.isPlaying && !_rotateController.isAnimating) {
      _rotateController.repeat();
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _rotateController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final radius = math.min(20.0, widget.size * 0.09);
    return AnimatedScale(
      duration: widget.motionDuration,
      curve: widget.motionCurve,
      scale: widget.isPlaying ? 1.018 : 1.0,
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (widget.isPlaying)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, _) {
                    final t = CurvedAnimation(
                      parent: _glowController,
                      curve: Curves.easeInOut,
                    ).value;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: meta.accentColor.withValues(
                              alpha: 0.22 + t * 0.18,
                            ),
                            blurRadius: 28 + t * 20,
                            spreadRadius: 2 + t * 4,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Positioned.fill(
              left: widget.size * 0.14,
              child: RotationTransition(
                turns: _rotateController,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF07090B),
                        _mixNativeAudioColors(
                          meta.primaryColor,
                          const Color(0xFF11151A),
                          0.30,
                        ),
                        const Color(0xFF050607),
                      ],
                      stops: const [0.18, 0.55, 1],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.30),
                        blurRadius: 26,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: widget.size * 0.26,
                      height: widget.size * 0.26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: meta.accentColor.withValues(alpha: 0.86),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.34),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              right: widget.size * 0.12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _mixNativeAudioColors(
                        meta.accentColor,
                        Colors.white,
                        0.72,
                      ),
                      meta.secondaryColor.withValues(alpha: 0.92),
                      _mixNativeAudioColors(
                        meta.primaryColor,
                        const Color(0xFF101316),
                        0.64,
                      ),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: meta.primaryColor.withValues(alpha: 0.26),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 40,
                      offset: const Offset(0, 22),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: 0.24),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.22),
                              ],
                              stops: const [0, 0.48, 1],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: widget.size * 0.10,
                        bottom: widget.size * 0.10,
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          size: widget.size * 0.16,
                          color: Colors.white.withValues(alpha: 0.54),
                        ),
                      ),
                      Center(
                        child: Text(
                          meta.coverGlyph,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: widget.foregroundColor.withValues(
                              alpha: 0.94,
                            ),
                            fontWeight: FontWeight.w900,
                            fontSize: widget.size * 0.28,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NativeAudioAnimatedBackdrop extends StatefulWidget {
  const _NativeAudioAnimatedBackdrop({
    required this.meta,
    required this.duration,
    required this.curve,
    required this.isDark,
  });

  final NativeAudioVisualMeta meta;
  final Duration duration;
  final Curve curve;
  final bool isDark;

  @override
  State<_NativeAudioAnimatedBackdrop> createState() =>
      _NativeAudioAnimatedBackdropState();
}

class _NativeAudioAnimatedBackdropState
    extends State<_NativeAudioAnimatedBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void initState() {
    super.initState();
    if (widget.duration > Duration.zero) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _NativeAudioAnimatedBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration <= Duration.zero) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentAlpha = widget.isDark ? 0.40 : 0.18;
    final highlightAlpha = widget.isDark ? 0.10 : 0.06;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = widget.curve.transform(_controller.value);
        return Transform.scale(
          scale: 1.04 + t * 0.030,
          child: Transform.translate(
            offset: Offset(-8 * t, 6 * t),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.55, -0.45),
                  radius: 1.15,
                  colors: [
                    widget.meta.accentColor.withValues(alpha: accentAlpha),
                    Colors.transparent,
                  ],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.72, -0.55),
                    radius: 0.8,
                    colors: [
                      widget.meta.primaryColor.withValues(alpha: highlightAlpha),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NativeAudioIconButton extends StatelessWidget {
  const _NativeAudioIconButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.prominent = false,
    this.active = false,
    this.compact = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool prominent;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = prominent ? 52.0 : (compact ? 32.0 : 38.0);
    return Tooltip(
      message: tooltip,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: kNativeAudioMotionCurve,
        scale: active ? 1.04 : 1.0,
        child: SizedBox.square(
          dimension: size,
          child: IconButton(
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: prominent
                  ? cs.primary.withValues(alpha: 0.14)
                  : active
                  ? cs.primary.withValues(alpha: 0.14)
                  : cs.onSurface.withValues(alpha: 0.06),
              foregroundColor: prominent
                  ? cs.primary
                  : active
                  ? cs.primary
                  : cs.onSurface,
              disabledForegroundColor: cs.onSurface.withValues(alpha: 0.28),
              shape: const CircleBorder(),
            ),
            onPressed: onPressed,
            icon: Icon(icon, size: prominent ? 30 : (compact ? 18 : 21)),
          ),
        ),
      ),
    );
  }
}

// 音效单按钮 → 点击弹出 PopupMenu
class _NativeAudioEffectMenuButton extends StatelessWidget {
  const _NativeAudioEffectMenuButton({
    required this.effect,
    required this.onSelect,
    required this.context,
  });

  final _NativeAudioEffect effect;
  final ValueChanged<_NativeAudioEffect> onSelect;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    final isZh = openHandIsChineseLocale(ctx);
    final label = isZh ? effect.zhLabel : effect.enLabel;
    return Tooltip(
      message: isZh ? '音效：$label' : 'Effect: $label',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showMenu(ctx, isZh, cs),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: kNativeAudioMotionCurve,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: effect != _NativeAudioEffect.standard
                ? cs.primary.withValues(alpha: 0.12)
                : cs.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: effect != _NativeAudioEffect.standard
                  ? cs.primary.withValues(alpha: 0.36)
                  : cs.outlineVariant.withValues(alpha: 0.60),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                effect.icon,
                size: 15,
                color: effect != _NativeAudioEffect.standard
                    ? cs.primary
                    : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: effect != _NativeAudioEffect.standard
                      ? cs.primary
                      : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: effect != _NativeAudioEffect.standard
                    ? cs.primary
                    : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext ctx, bool isZh, ColorScheme cs) {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    showMenu<_NativeAudioEffect>(
      context: ctx,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy - _NativeAudioEffect.values.length * 44.0 - 8,
        offset.dx + size.width,
        offset.dy,
      ),
      items: _NativeAudioEffect.values.map((e) {
        final eLabel = isZh ? e.zhLabel : e.enLabel;
        return PopupMenuItem<_NativeAudioEffect>(
          value: e,
          child: Row(
            children: [
              Icon(
                e.icon,
                size: 18,
                color: e == effect ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                eLabel,
                style: TextStyle(
                  color: e == effect ? cs.primary : cs.onSurface,
                  fontWeight:
                      e == effect ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (e == effect) ...[
                const Spacer(),
                Icon(Icons.check_rounded, size: 16, color: cs.primary),
              ],
            ],
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null) onSelect(selected);
    });
  }
}

class _NativeAudioTimeText extends StatelessWidget {
  const _NativeAudioTimeText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      value,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

const List<(Color, Color, Color)> _kNativeAudioPalettes =
    <(Color, Color, Color)>[
      (Color(0xFF76815E), Color(0xFFBFC79A), Color(0xFFF4F0D7)),
      (Color(0xFF5C6E75), Color(0xFFA9C3BD), Color(0xFFE8F0E9)),
      (Color(0xFF765F73), Color(0xFFD2A9B8), Color(0xFFF4E5EA)),
      (Color(0xFF6F6B55), Color(0xFFD1C394), Color(0xFFF1E8C8)),
      (Color(0xFF59705C), Color(0xFFAEC8A8), Color(0xFFE8F3DF)),
    ];

String normalizeNativeAudioText(String value, {required String fallback}) {
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

String deriveNativeAudioArtist(String detail) {
  final leaf = _prettyNativeAudioLeaf(detail);
  final segments = leaf
      .split(RegExp(r'[-_]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (segments.length >= 2 && segments.first.length <= 28) {
    return segments.first;
  }
  if (_looksLikeGeneratedAudioName(leaf)) {
    return 'AI 音频';
  }
  return 'OpenHand 音频';
}

String deriveNativeAudioAlbum(String detail) {
  final leaf = _prettyNativeAudioLeaf(detail);
  if (_looksLikeGeneratedAudioName(leaf)) {
    return '生成音频';
  }
  return leaf.length <= 32 ? leaf : '音频预览';
}

String lastNativeAudioPathOrUrlSegment(String value) {
  final parsed = Uri.tryParse(value);
  final segments = parsed?.pathSegments.where((segment) => segment.isNotEmpty);
  final lastSegment = segments == null || segments.isEmpty
      ? null
      : segments.last;
  if (lastSegment != null && lastSegment.trim().isNotEmpty) {
    return Uri.decodeComponent(lastSegment);
  }
  return p.basename(value.replaceAll('\\', '/'));
}

List<String> deriveNativeAudioLyrics(String title, String detail) {
  final leaf = _prettyNativeAudioLeaf(detail);
  final titleNormalized = normalizeNativeAudioText(title, fallback: 'Audio');
  if (_looksLikeGeneratedAudioName(leaf) || leaf == titleNormalized) {
    return const <String>[];
  }
  return <String>{
    titleNormalized,
    leaf,
  }.where((line) => line.trim().isNotEmpty).take(4).toList(growable: false);
}

String _prettyNativeAudioLeaf(String detail) {
  final leaf = normalizeNativeAudioText(
    lastNativeAudioPathOrUrlSegment(detail),
    fallback: detail,
  );
  if (_looksLikeGeneratedAudioName(leaf)) {
    return '生成音频';
  }
  return leaf;
}

bool _looksLikeGeneratedAudioName(String value) {
  final normalized = value.trim().toLowerCase();
  return RegExp(r'^audio[_-]?\d+$').hasMatch(normalized) ||
      RegExp(r'^audio[_-]').hasMatch(normalized);
}

String _formatNativeAudioTime(Duration value) {
  if (value <= Duration.zero) return '00:00';
  final total = value.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

Duration _clampDuration(Duration value, Duration max) {
  if (value < Duration.zero) return Duration.zero;
  if (max > Duration.zero && value > max) return max;
  return value;
}

Color _mixNativeAudioColors(Color color, Color other, double colorWeight) {
  return Color.lerp(other, color, colorWeight.clamp(0.0, 1.0)) ?? color;
}

String _extensionForAudioMime(String? mimeType) {
  return switch (mimeType?.toLowerCase()) {
    'audio/wav' || 'audio/wave' || 'audio/x-wav' => 'wav',
    'audio/mp4' || 'audio/m4a' || 'audio/x-m4a' => 'm4a',
    'audio/aac' => 'aac',
    'audio/ogg' || 'audio/opus' => 'ogg',
    'audio/flac' || 'audio/x-flac' => 'flac',
    _ => 'mp3',
  };
}
