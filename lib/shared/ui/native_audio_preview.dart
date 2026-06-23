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
      final duration = await _player.getDuration().timeout(
        kNativeAudioControlTimeout,
        onTimeout: () => null,
      );
      if (_disposed || !mounted || serial != _bootstrapSerial) return;
      setState(() {
        _duration = duration ?? Duration.zero;
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
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : widget.motionDuration;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackSize = MediaQuery.sizeOf(context);
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackSize.width;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallbackSize.height;
        final useWide =
            width >= _kNativeAudioWideBreakpoint &&
            height >= _kNativeAudioShortBreakpoint;
        final horizontalPadding = useWide ? 36.0 : 16.0;
        final verticalPadding = useWide ? 24.0 : 16.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF101316),
                _mixNativeAudioColors(
                  meta.primaryColor,
                  const Color(0xFF151A1F),
                  0.28,
                ),
                _mixNativeAudioColors(
                  meta.secondaryColor,
                  const Color(0xFF201821),
                  0.22,
                ),
              ],
            ),
          ),
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _NativeAudioAnimatedBackdrop(
                    meta: meta,
                    duration: duration,
                    curve: widget.motionCurve,
                  ),
                ),
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: widget.motionCurve,
                    switchOutCurve: Curves.easeOutCubic,
                    child: Padding(
                      key: ValueKey<bool>(useWide),
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalPadding,
                      ),
                      child: useWide
                          ? _buildWide(context)
                          : _buildCompact(context),
                    ),
                  ),
                ),
                if (_loading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x55000000),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
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
    return Row(
      children: [
        Expanded(flex: 90, child: _buildAlbumColumn(context, compact: false)),
        const SizedBox(width: 34),
        Expanded(flex: 110, child: _buildLyricsColumn(context)),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < 420;
        return Column(
          children: [
            Expanded(child: _buildAlbumColumn(context, compact: true)),
            if (!short) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: math.min(112, constraints.maxHeight * 0.28),
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
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallback.width;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallback.height;
        final short = height < 500;
        final coverLimit = compact ? 148.0 : (short ? 218.0 : 246.0);
        final coverSize = math
            .min(
              coverLimit,
              math.min(
                width * (compact ? 0.34 : 0.54),
                height * (short ? 0.34 : 0.40),
              ),
            )
            .clamp(compact ? 82.0 : 154.0, coverLimit)
            .toDouble();
        final gap = compact || short ? 8.0 : 12.0;
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              child: _NativeAudioAlbumCover(
                meta: meta,
                size: coverSize,
                foregroundColor: Colors.white,
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
            _buildTransport(context),
            SizedBox(height: gap),
            _buildEffectStrip(context),
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
    final meta = widget.meta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          meta.album,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.60),
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          meta.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            fontSize: compact ? 18 : 22,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${meta.artist} · ${meta.detail}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.70),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 8,
            activeTrackColor: Colors.white.withValues(alpha: 0.92),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.24),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.18),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Slider(
            value: progress,
            onChanged: _sourceReady
                ? (value) {
                    final target = Duration(
                      milliseconds: (_duration.inMilliseconds * value).round(),
                    );
                    setState(() => _position = target);
                  }
                : null,
            onChangeEnd: _sourceReady
                ? (value) {
                    final target = Duration(
                      milliseconds: (_duration.inMilliseconds * value).round(),
                    );
                    unawaited(_seekTo(target));
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
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

  Widget _buildTransport(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _NativeAudioIconButton(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '后退 15 秒',
                    en: 'Back 15 seconds',
                  ),
                  icon: Icons.replay_10_rounded,
                  onPressed: _sourceReady
                      ? () => unawaited(_seekBy(-kNativeAudioSeekStep))
                      : null,
                ),
                const SizedBox(width: 10),
                _NativeAudioIconButton(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: _isPlaying ? '暂停' : '播放',
                    en: _isPlaying ? 'Pause' : 'Play',
                  ),
                  icon: _isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  prominent: true,
                  onPressed: _sourceReady
                      ? () => unawaited(_togglePlayPause())
                      : null,
                ),
                const SizedBox(width: 10),
                _NativeAudioIconButton(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '快进 15 秒',
                    en: 'Forward 15 seconds',
                  ),
                  icon: Icons.forward_10_rounded,
                  onPressed: _sourceReady
                      ? () => unawaited(_seekBy(kNativeAudioSeekStep))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _NativeAudioIconButton(
                  tooltip: _playModeTooltip(context),
                  icon: _playModeIcon,
                  active: _playMode != _NativeAudioPlayMode.sequence,
                  compact: true,
                  onPressed: _cyclePlayMode,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _playModeLabel(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.70),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: constraints.maxWidth < 260 ? 2 : 3,
                  child: _buildVolumeControl(context),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildVolumeControl(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NativeAudioIconButton(
          tooltip: openHandLocalizedText(
            context,
            zh: _muted ? '取消静音' : '静音',
            en: _muted ? 'Unmute' : 'Mute',
          ),
          icon: _muted || _volume <= 0
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
          compact: true,
          onPressed: () => unawaited(_toggleMuted()),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: Colors.white.withValues(alpha: 0.88),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: _muted ? 0 : _volume,
              onChanged: (value) => unawaited(_setVolume(value)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEffectStrip(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final effect in _NativeAudioEffect.values) ...[
              _NativeAudioEffectChip(
                label: isZh ? effect.zhLabel : effect.enLabel,
                icon: effect.icon,
                selected: _effect == effect,
                onPressed: () => unawaited(_setEffect(effect)),
              ),
              if (effect != _NativeAudioEffect.values.last)
                const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLyricsColumn(BuildContext context, {bool compact = false}) {
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
            color: Colors.white.withValues(alpha: 0.52),
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: compact ? 6 : 14),
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
              stops: [0, 0.16, 0.84, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(vertical: compact ? 4 : 12),
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
                      color: Colors.white.withValues(
                        alpha: selected ? 0.95 : 0.50,
                      ),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                      fontSize: compact ? 15 : 20,
                      height: 1.22,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: compact ? 3 : 7),
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
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.58),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => unawaited(_bootstrap()),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          openHandLocalizedText(context, zh: '重试', en: 'Retry'),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.46),
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

  String _playModeLabel(BuildContext context) {
    return switch (_playMode) {
      _NativeAudioPlayMode.sequence => openHandLocalizedText(
        context,
        zh: '顺序',
        en: 'Sequence',
      ),
      _NativeAudioPlayMode.repeatOne => openHandLocalizedText(
        context,
        zh: '单曲',
        en: 'Repeat',
      ),
      _NativeAudioPlayMode.shuffle => openHandLocalizedText(
        context,
        zh: '随机',
        en: 'Shuffle',
      ),
    };
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _NativeAudioAlbumCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final radius = math.min(20.0, widget.size * 0.09);
    return AnimatedScale(
      duration: widget.motionDuration,
      curve: widget.motionCurve,
      scale: widget.isPlaying ? 1.015 : 1.0,
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              left: widget.size * 0.14,
              child: RotationTransition(
                turns: _controller,
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
  });

  final NativeAudioVisualMeta meta;
  final Duration duration;
  final Curve curve;

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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = widget.curve.transform(_controller.value);
        return Transform.scale(
          scale: 1.04 + t * 0.035,
          child: Transform.translate(
            offset: Offset(-10 * t, 8 * t),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.55, -0.45),
                  radius: 1.15,
                  colors: [
                    _mixNativeAudioColors(
                      widget.meta.accentColor,
                      Colors.transparent,
                      0.50,
                    ),
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
                      Colors.white.withValues(alpha: 0.16),
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
    final size = prominent ? 54.0 : (compact ? 30.0 : 36.0);
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
                  ? Colors.white.withValues(alpha: 0.24)
                  : active
                  ? Colors.white.withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.10),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white.withValues(alpha: 0.36),
              shape: const CircleBorder(),
            ),
            onPressed: onPressed,
            icon: Icon(icon, size: prominent ? 31 : (compact ? 18 : 22)),
          ),
        ),
      ),
    );
  }
}

class _NativeAudioEffectChip extends StatelessWidget {
  const _NativeAudioEffectChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 160),
      curve: kNativeAudioMotionCurve,
      scale: selected ? 1.02 : 1.0,
      child: ChoiceChip(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        selected: selected,
        onSelected: (_) => onPressed(),
        avatar: Icon(icon, size: 15),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        labelStyle: TextStyle(
          color: selected
              ? const Color(0xFF1F241C)
              : Colors.white.withValues(alpha: 0.78),
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          fontSize: 12,
        ),
        selectedColor: Colors.white.withValues(alpha: 0.86),
        backgroundColor: Colors.white.withValues(alpha: 0.10),
        side: BorderSide(
          color: Colors.white.withValues(alpha: selected ? 0.90 : 0.18),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

class _NativeAudioTimeText extends StatelessWidget {
  const _NativeAudioTimeText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Colors.white.withValues(alpha: 0.74),
        fontWeight: FontWeight.w800,
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
  final leaf = lastNativeAudioPathOrUrlSegment(detail);
  final segments = normalizeNativeAudioText(leaf, fallback: detail)
      .split(RegExp(r'[-_]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (segments.length >= 2 && segments.first.length <= 28) {
    return segments.first;
  }
  return 'OpenHand Audio';
}

String deriveNativeAudioAlbum(String detail) {
  final leaf = lastNativeAudioPathOrUrlSegment(detail);
  final normalized = normalizeNativeAudioText(leaf, fallback: 'Preview Album');
  return normalized.length <= 32 ? normalized : 'Preview Album';
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
  final leaf = normalizeNativeAudioText(
    lastNativeAudioPathOrUrlSegment(detail),
    fallback: detail,
  );
  return <String>{
    title,
    leaf,
    'AI 生成音频',
    '正在播放当前媒体',
    '可调节音量、进度与音效',
    'OpenHand 音频预览',
  }.where((line) => line.trim().isNotEmpty).take(6).toList(growable: false);
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
