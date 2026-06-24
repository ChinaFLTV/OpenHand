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
const Size kNativeAudioPreviewPreferredSize = Size(640, 560);
const Duration _kNativeAudioPollInterval = Duration(milliseconds: 250);
const Duration _kNativeAudioMetadataPollTimeout = Duration(milliseconds: 450);
const Duration _kNativeAudioDurationProbeInterval = Duration(milliseconds: 180);
const Duration _kNativeAudioSeekSettleDelay = Duration(milliseconds: 140);
const Duration _kNativeAudioSeekEchoGuard = Duration(milliseconds: 900);
const Duration _kNativeAudioSeekEchoMinTarget = Duration(milliseconds: 900);
const Duration _kNativeAudioSeekEchoTolerance = Duration(milliseconds: 1800);
const int _kNativeAudioDurationProbeAttempts = 8;
const int _kNativeAudioHeaderProbeBytes = 256 * 1024;
const double _kNativeAudioWideBreakpoint = 540;
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
  bool _manualProgressActive = false;
  String? _loadError;
  String? _tempAudioPath;
  Timer? _progressPollTimer;
  int _bootstrapSerial = 0;
  bool _pollInFlight = false;
  Duration? _seekEchoTarget;
  DateTime? _seekEchoGuardUntil;

  bool get _isPlaying => _playerState == PlayerState.playing;
  bool get _canScrub => _sourceReady && _duration > Duration.zero;
  bool get _hasMeaningfulAlbumLabel {
    final album = widget.meta.album.trim();
    if (album.isEmpty) return false;
    final normalizedAlbum = album.toLowerCase();
    return normalizedAlbum != widget.meta.title.trim().toLowerCase() &&
        normalizedAlbum != '生成音频' &&
        normalizedAlbum != '音频预览' &&
        normalizedAlbum != 'generated audio' &&
        normalizedAlbum != 'preview album';
  }

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
          _setKnownDuration(duration);
        }),
      )
      ..add(
        _player.onPositionChanged.listen((position) {
          if (!mounted ||
              _seeking ||
              _manualProgressActive ||
              position < Duration.zero) {
            return;
          }
          _setKnownPosition(position);
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
    _progressPollTimer?.cancel();
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
      _clearSeekEchoGuard();
    });
    try {
      await _stopForSourceReset();
      await _deleteTempAudioFile();
      await _player
          .setReleaseMode(ReleaseMode.stop)
          .timeout(kNativeAudioControlTimeout);
      await _player
          .setPlayerMode(PlayerMode.mediaPlayer)
          .timeout(kNativeAudioControlTimeout);
      await _player
          .setVolume(_effectiveVolume)
          .timeout(kNativeAudioControlTimeout);
      final source = await _buildAudioSource();
      await _player.setSource(source).timeout(kNativeAudioLoadTimeout);
      final duration = await _resolveBestDuration();
      _restartProgressPolling();
      if (_disposed || !mounted || serial != _bootstrapSerial) return;
      setState(() {
        _duration = duration;
        _loading = false;
        _sourceReady = true;
        _loadError = null;
      });
      if (duration <= Duration.zero) {
        unawaited(_refreshDurationWhenAvailable(serial));
      }
      unawaited(_pollPlaybackState());
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
      _kNativeAudioMetadataPollTimeout,
      onTimeout: () => null,
    );
    if (initial != null && initial > Duration.zero) return initial;
    for (
      var attempt = 0;
      attempt < _kNativeAudioDurationProbeAttempts;
      attempt++
    ) {
      await Future<void>.delayed(_kNativeAudioDurationProbeInterval);
      final next = await _player.getDuration().timeout(
        _kNativeAudioMetadataPollTimeout,
        onTimeout: () => null,
      );
      if (next != null && next > Duration.zero) return next;
    }
    return Duration.zero;
  }

  Future<Duration> _resolveBestDuration() async {
    final localDuration = await _resolveLocalDurationHint();
    if (localDuration != null && localDuration > Duration.zero) {
      return localDuration;
    }
    return _resolveDuration();
  }

  Future<void> _refreshDurationWhenAvailable(int serial) async {
    final duration = await _resolveBestDuration();
    if (_disposed ||
        !mounted ||
        serial != _bootstrapSerial ||
        duration <= Duration.zero) {
      return;
    }
    _setKnownDuration(duration);
  }

  Future<Duration?> _resolveLocalDurationHint() async {
    if (kIsWeb) return null;
    final path = widget.source.filePath ?? _tempAudioPath;
    if (path == null || path.trim().isEmpty) return null;
    try {
      return await estimateNativeAudioFileDuration(
        path,
        widget.source.mimeType,
      ).timeout(kNativeAudioControlTimeout, onTimeout: () => null);
    } catch (error, stack) {
      silentLog('native_audio_preview', 'resolve local duration', error, stack);
      return null;
    }
  }

  void _restartProgressPolling() {
    _progressPollTimer?.cancel();
    _progressPollTimer = Timer.periodic(_kNativeAudioPollInterval, (_) {
      unawaited(_pollPlaybackState());
    });
  }

  Future<void> _pollPlaybackState() async {
    if (_disposed ||
        !mounted ||
        _pollInFlight ||
        _seeking ||
        _manualProgressActive) {
      return;
    }
    _pollInFlight = true;
    try {
      final polledPosition = await _player.getCurrentPosition().timeout(
        _kNativeAudioMetadataPollTimeout,
        onTimeout: () => null,
      );
      final polledDuration = await _player.getDuration().timeout(
        _kNativeAudioMetadataPollTimeout,
        onTimeout: () => null,
      );
      if (!mounted || _disposed) return;
      final nextDuration =
          polledDuration != null && polledDuration > Duration.zero
          ? polledDuration
          : _duration;
      final acceptedPosition =
          polledPosition != null && polledPosition >= Duration.zero
          ? _acceptedReportedPosition(polledPosition, nextDuration)
          : null;
      final nextPosition = acceptedPosition ?? _position;
      if (nextDuration == _duration && nextPosition == _position) return;
      setState(() {
        _duration = nextDuration;
        _position = nextPosition;
      });
    } catch (error, stack) {
      silentLog(
        'native_audio_preview',
        'poll playback state failed',
        error,
        stack,
      );
    } finally {
      _pollInFlight = false;
    }
  }

  void _setKnownDuration(Duration duration) {
    if (duration <= Duration.zero || !mounted) return;
    if (_duration == duration) return;
    setState(() {
      _duration = duration;
      _position = _clampDuration(_position, _duration);
    });
  }

  void _setKnownPosition(Duration position) {
    if (position < Duration.zero || !mounted) return;
    final nextPosition = _acceptedReportedPosition(position, _duration);
    if (nextPosition == null) return;
    if (nextPosition == _position) return;
    setState(() => _position = nextPosition);
  }

  Duration? _acceptedReportedPosition(Duration reported, Duration duration) {
    final candidate = _clampDuration(reported, duration);
    if (_shouldIgnoreSeekEcho(candidate)) return null;
    _clearSeekEchoGuardIfSettled(candidate);
    return candidate;
  }

  bool _shouldIgnoreSeekEcho(Duration candidate) {
    final target = _seekEchoTarget;
    if (target == null || !_hasActiveSeekEchoGuard) return false;
    if (target <= _kNativeAudioSeekEchoMinTarget) return false;
    return _durationDistance(candidate, target) >
        _kNativeAudioSeekEchoTolerance;
  }

  void _clearSeekEchoGuardIfSettled(Duration candidate) {
    final target = _seekEchoTarget;
    if (target == null) return;
    if (_durationDistance(candidate, target) <=
        _kNativeAudioSeekEchoTolerance) {
      _clearSeekEchoGuard();
    }
  }

  bool get _hasActiveSeekEchoGuard {
    final guardUntil = _seekEchoGuardUntil;
    if (guardUntil == null) return false;
    if (DateTime.now().isBefore(guardUntil)) return true;
    _clearSeekEchoGuard();
    return false;
  }

  void _markSeekEchoGuard(Duration target) {
    _seekEchoTarget = target;
    _seekEchoGuardUntil = DateTime.now().add(_kNativeAudioSeekEchoGuard);
  }

  void _clearSeekEchoGuard() {
    _seekEchoTarget = null;
    _seekEchoGuardUntil = null;
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
    _restartProgressPolling();
  }

  Future<void> _seekBy(Duration delta) async {
    await _seekTo(_position + delta);
  }

  Future<void> _seekTo(Duration target) async {
    if (!_sourceReady) return;
    final upperBound = _duration > Duration.zero
        ? _duration
        : Duration(
            milliseconds: math.max(
              target.inMilliseconds,
              _position.inMilliseconds,
            ),
          );
    final clamped = _clampDuration(target, upperBound);
    setState(() {
      _seeking = true;
      _position = clamped;
      _markSeekEchoGuard(clamped);
    });
    try {
      await _player.seek(clamped).timeout(kNativeAudioControlTimeout);
      await Future<void>.delayed(_kNativeAudioSeekSettleDelay);
      final actualPosition = await _player.getCurrentPosition().timeout(
        kNativeAudioControlTimeout,
        onTimeout: () => null,
      );
      final actualDuration = await _player.getDuration().timeout(
        kNativeAudioControlTimeout,
        onTimeout: () => null,
      );
      if (!mounted || _disposed) return;
      setState(() {
        var nextDuration = _duration;
        if (actualDuration != null && actualDuration > Duration.zero) {
          nextDuration = actualDuration;
        }
        _duration = nextDuration;
        if (actualPosition != null && actualPosition >= Duration.zero) {
          final accepted = _acceptedReportedPosition(
            actualPosition,
            nextDuration,
          );
          _position = accepted ?? _clampDuration(clamped, nextDuration);
        } else {
          _position = _clampDuration(clamped, nextDuration);
        }
      });
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
    final quietTint = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.045),
      colorScheme.surfaceContainerHighest,
    );
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
                      quietTint,
                      colorScheme.brightness == Brightness.dark ? 0.36 : 0.62,
                    ) ??
                    baseColor,
                Color.lerp(
                      baseColor,
                      colorScheme.surfaceContainerLow,
                      colorScheme.brightness == Brightness.dark ? 0.50 : 0.78,
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
                      child: Center(
                        child: _buildAlbumColumn(context, compact: !useWide),
                      ),
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
        final coverLimit = compact ? 144.0 : (short ? 210.0 : 240.0);
        final coverBase = compact
            ? math.min(width * 0.42, height * 0.34)
            : math.min(width * 0.50, height * 0.42);
        final coverSize = math
            .min(coverLimit, coverBase)
            .clamp(compact ? 92.0 : 180.0, coverLimit)
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
        return Align(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: compact ? 420 : 500,
              minWidth: compact ? 280 : 360,
            ),
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildTrackMeta(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final meta = widget.meta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          _hasMeaningfulAlbumLabel
              ? '${meta.artist} · ${meta.album}'
              : meta.artist,
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
            onChangeStart: _canScrub
                ? (_) => setState(() => _manualProgressActive = true)
                : null,
            onChanged: _canScrub
                ? (value) {
                    final target = Duration(
                      milliseconds: (_duration.inMilliseconds * value).round(),
                    );
                    setState(() => _position = target);
                  }
                : null,
            onChangeEnd: _canScrub
                ? (value) {
                    final target = Duration(
                      milliseconds: (_duration.inMilliseconds * value).round(),
                    );
                    setState(() => _manualProgressActive = false);
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
          onPressed: _sourceReady
              ? () => unawaited(_seekBy(-kNativeAudioSeekStep))
              : null,
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
          onPressed: _sourceReady ? () => unawaited(_togglePlayPause()) : null,
        ),
        const SizedBox(width: 12),
        _NativeAudioIconButton(
          tooltip: openHandLocalizedText(
            context,
            zh: '快进 15 秒',
            en: 'Forward 15 s',
          ),
          icon: Icons.forward_10_rounded,
          onPressed: _sourceReady
              ? () => unawaited(_seekBy(kNativeAudioSeekStep))
              : null,
        ),
      ],
    );
  }

  // 底部控制栏：播放模式 | 音量 | 音效
  Widget _buildControlsBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 10,
          children: [
            _NativeAudioIconButton(
              tooltip: _playModeTooltip(context),
              icon: _playModeIcon,
              active: _playMode != _NativeAudioPlayMode.sequence,
              compact: true,
              onPressed: _cyclePlayMode,
            ),
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
            SizedBox(
              width: narrow ? 136 : 180,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: cs.primary,
                  inactiveTrackColor: cs.outlineVariant,
                  thumbColor: cs.primary,
                  overlayColor: cs.primary.withValues(alpha: 0.12),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 11,
                  ),
                ),
                child: Slider(
                  value: _muted ? 0.0 : _volume,
                  onChanged: (value) => unawaited(_setVolume(value)),
                ),
              ),
            ),
            _NativeAudioEffectMenuButton(
              effect: _effect,
              onSelect: (effect) => unawaited(_setEffect(effect)),
              context: context,
            ),
          ],
        );
      },
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
                  Icon(Icons.error_outline_rounded, color: cs.error, size: 30),
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
                          openHandLocalizedText(context, zh: '重试', en: 'Retry'),
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
    duration: const Duration(seconds: 24),
  );
  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
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
    final colorScheme = Theme.of(context).colorScheme;
    final meta = widget.meta;
    final radius = math.min(20.0, widget.size * 0.09);
    final coverBase = Color.alphaBlend(
      meta.primaryColor.withValues(alpha: 0.08),
      colorScheme.primaryContainer,
    );
    final coverMid = Color.alphaBlend(
      colorScheme.secondary.withValues(alpha: 0.16),
      colorScheme.surfaceContainerHighest,
    );
    final coverEnd = Color.alphaBlend(
      meta.secondaryColor.withValues(alpha: 0.08),
      colorScheme.surfaceContainerHigh,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_rotateController, _glowController]),
      builder: (context, child) {
        final breath = widget.isPlaying && !reduceMotion
            ? Curves.easeInOutCubic.transform(_glowController.value)
            : 0.0;
        final playLift = widget.isPlaying && !reduceMotion ? 1.0 : 0.0;
        final scale = 1.0 + playLift * 0.012 + breath * 0.010;
        final lift = -playLift * (1.0 + breath * 2.2);
        return Transform.translate(
          offset: Offset(0, lift),
          child: Transform.scale(
            scale: scale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(
                      alpha: 0.13 + breath * 0.07,
                    ),
                    blurRadius: 24 + breath * 16,
                    spreadRadius: breath * 1.2,
                    offset: Offset(0, 12 + breath * 4),
                  ),
                  BoxShadow(
                    color: colorScheme.shadow.withValues(
                      alpha: 0.10 + breath * 0.03,
                    ),
                    blurRadius: 30 + breath * 8,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
      child: SizedBox.square(
        dimension: widget.size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [coverBase, coverMid, coverEnd],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: RotationTransition(
                    turns: _rotateController,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: SweepGradient(
                          colors: [
                            colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.10,
                            ),
                            Colors.transparent,
                            colorScheme.primary.withValues(alpha: 0.08),
                            colorScheme.shadow.withValues(alpha: 0.06),
                            colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.10,
                            ),
                          ],
                          stops: const [0, 0.28, 0.50, 0.74, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.onPrimaryContainer.withValues(
                            alpha: 0.16,
                          ),
                          Colors.transparent,
                          colorScheme.shadow.withValues(alpha: 0.13),
                        ],
                        stops: const [0, 0.50, 1],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: widget.size * 0.30,
                    height: widget.size * 0.30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.surface.withValues(alpha: 0.42),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.72,
                        ),
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
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.40),
                  ),
                ),
                Center(
                  child: Text(
                    meta.coverGlyph,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      color: widget.foregroundColor.withValues(alpha: 0.94),
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
    final colorScheme = Theme.of(context).colorScheme;
    final accentAlpha = widget.isDark ? 0.20 : 0.10;
    final highlightAlpha = widget.isDark ? 0.11 : 0.07;
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
                    colorScheme.primary.withValues(alpha: accentAlpha),
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
                      colorScheme.tertiary.withValues(alpha: highlightAlpha),
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
                  fontWeight: e == effect ? FontWeight.w700 : FontWeight.w500,
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

Future<Duration?> estimateNativeAudioFileDuration(
  String filePath,
  String? mimeType,
) async {
  final file = File(filePath);
  if (!await file.exists()) return null;
  final length = await file.length();
  if (length <= 0) return null;
  final normalizedMime = mimeType?.split(';').first.trim().toLowerCase();
  final extension = p.extension(filePath).toLowerCase();
  final kind = _nativeAudioContainerKind(extension, normalizedMime);
  if (kind != null) {
    final duration = await _estimateNativeAudioDurationByKind(
      file,
      length,
      kind,
    );
    if (duration != null) return duration;
  }
  return _estimateNativeAudioDurationBySniffing(file, length);
}

String? _nativeAudioContainerKind(String extension, String? mimeType) {
  if (mimeType == 'audio/mpeg' ||
      mimeType == 'audio/mp3' ||
      extension == '.mp3') {
    return 'mp3';
  }
  if (mimeType == 'audio/wav' ||
      mimeType == 'audio/wave' ||
      mimeType == 'audio/x-wav' ||
      extension == '.wav') {
    return 'wav';
  }
  if (mimeType == 'audio/mp4' ||
      mimeType == 'audio/m4a' ||
      mimeType == 'audio/x-m4a' ||
      extension == '.m4a' ||
      extension == '.mp4') {
    return 'mp4';
  }
  return null;
}

Future<Duration?> _estimateNativeAudioDurationByKind(
  File file,
  int length,
  String kind,
) {
  return switch (kind) {
    'mp3' => _estimateMp3Duration(file, length),
    'wav' => _estimateWavDuration(file, length),
    'mp4' => _estimateMp4Duration(file, length),
    _ => Future<Duration?>.value(),
  };
}

Future<Duration?> _estimateNativeAudioDurationBySniffing(
  File file,
  int length,
) async {
  final raf = await file.open();
  try {
    final header = await _readAt(raf, 0, math.min(16, length).toInt());
    if (_asciiEquals(header, 0, 'ID3') ||
        (header.length >= 2 &&
            header[0] == 0xFF &&
            (header[1] & 0xE0) == 0xE0)) {
      return _estimateMp3Duration(file, length);
    }
    if (_asciiEquals(header, 0, 'RIFF') && _asciiEquals(header, 8, 'WAVE')) {
      return _estimateWavDuration(file, length);
    }
    if (_asciiEquals(header, 4, 'ftyp')) {
      return _estimateMp4Duration(file, length);
    }
    return null;
  } finally {
    await raf.close();
  }
}

Future<Duration?> _estimateMp3Duration(File file, int length) async {
  final raf = await file.open();
  try {
    final probe = await _readAt(
      raf,
      0,
      math.min(_kNativeAudioHeaderProbeBytes, length).toInt(),
    );
    final start = _mp3AudioStartOffset(probe);
    final frameOffset = _findMp3FrameOffset(probe, start);
    if (frameOffset == null) return null;
    final frame = _parseMp3FrameHeader(probe, frameOffset);
    if (frame == null) return null;
    final xingDuration = _readMp3XingDuration(probe, frameOffset, frame);
    if (xingDuration != null) return xingDuration;

    var audioBytes = math.max(0, length - frameOffset);
    if (length >= 128) {
      final tail = await _readAt(raf, length - 128, 128);
      if (_asciiEquals(tail, 0, 'TAG')) {
        audioBytes = math.max(0, audioBytes - 128);
      }
    }
    if (audioBytes <= 0 || frame.bitrate <= 0) return null;
    return _durationFromSeconds((audioBytes * 8) / frame.bitrate);
  } finally {
    await raf.close();
  }
}

int _mp3AudioStartOffset(Uint8List bytes) {
  if (!_asciiEquals(bytes, 0, 'ID3') || bytes.length < 10) return 0;
  final size = _readSynchsafeUint32(bytes, 6);
  if (size == null) return 0;
  final hasFooter = (bytes[5] & 0x10) != 0;
  final offset = 10 + size + (hasFooter ? 10 : 0);
  return offset < bytes.length ? offset : 0;
}

int? _findMp3FrameOffset(Uint8List bytes, int start) {
  for (var offset = math.max(0, start); offset + 4 <= bytes.length; offset++) {
    if (_parseMp3FrameHeader(bytes, offset) != null) return offset;
  }
  return null;
}

_Mp3Frame? _parseMp3FrameHeader(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 4 > bytes.length) return null;
  final header = _readUint32BE(bytes, offset);
  if ((header & 0xFFE00000) != 0xFFE00000) return null;
  final versionBits = (header >> 19) & 0x3;
  final layerBits = (header >> 17) & 0x3;
  final bitrateIndex = (header >> 12) & 0xF;
  final sampleRateIndex = (header >> 10) & 0x3;
  final channelMode = (header >> 6) & 0x3;
  if (versionBits == 1 ||
      layerBits == 0 ||
      bitrateIndex == 0 ||
      bitrateIndex == 0xF ||
      sampleRateIndex == 0x3) {
    return null;
  }
  final layer = switch (layerBits) {
    3 => 1,
    2 => 2,
    1 => 3,
    _ => 0,
  };
  final bitrateKbps = _mp3BitrateKbps(versionBits, layer, bitrateIndex);
  final sampleRate = _mp3SampleRate(versionBits, sampleRateIndex);
  if (bitrateKbps == null || sampleRate == null || layer == 0) return null;
  return _Mp3Frame(
    versionBits: versionBits,
    layer: layer,
    bitrate: bitrateKbps * 1000,
    sampleRate: sampleRate,
    samplesPerFrame: _mp3SamplesPerFrame(versionBits, layer),
    channelMode: channelMode,
  );
}

int? _mp3BitrateKbps(int versionBits, int layer, int index) {
  const mpeg1Layer1 = <int>[
    32,
    64,
    96,
    128,
    160,
    192,
    224,
    256,
    288,
    320,
    352,
    384,
    416,
    448,
  ];
  const mpeg1Layer2 = <int>[
    32,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    160,
    192,
    224,
    256,
    320,
    384,
  ];
  const mpeg1Layer3 = <int>[
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    160,
    192,
    224,
    256,
    320,
  ];
  const mpeg2Layer1 = <int>[
    32,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    144,
    160,
    176,
    192,
    224,
    256,
  ];
  const mpeg2Layer23 = <int>[
    8,
    16,
    24,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    144,
    160,
  ];
  final table = versionBits == 3
      ? switch (layer) {
          1 => mpeg1Layer1,
          2 => mpeg1Layer2,
          3 => mpeg1Layer3,
          _ => null,
        }
      : (layer == 1 ? mpeg2Layer1 : mpeg2Layer23);
  if (table == null || index < 1 || index > table.length) return null;
  return table[index - 1];
}

int? _mp3SampleRate(int versionBits, int index) {
  const mpeg1 = <int>[44100, 48000, 32000];
  const mpeg2 = <int>[22050, 24000, 16000];
  const mpeg25 = <int>[11025, 12000, 8000];
  final table = switch (versionBits) {
    3 => mpeg1,
    2 => mpeg2,
    0 => mpeg25,
    _ => null,
  };
  if (table == null || index < 0 || index >= table.length) return null;
  return table[index];
}

int _mp3SamplesPerFrame(int versionBits, int layer) {
  if (layer == 1) return 384;
  if (layer == 2) return 1152;
  return versionBits == 3 ? 1152 : 576;
}

Duration? _readMp3XingDuration(
  Uint8List bytes,
  int frameOffset,
  _Mp3Frame frame,
) {
  final xingOffset =
      frameOffset +
      (frame.versionBits == 3
          ? (frame.channelMode == 3 ? 21 : 36)
          : (frame.channelMode == 3 ? 13 : 21));
  if (xingOffset + 16 > bytes.length) return null;
  if (!_asciiEquals(bytes, xingOffset, 'Xing') &&
      !_asciiEquals(bytes, xingOffset, 'Info')) {
    return null;
  }
  final flags = _readUint32BE(bytes, xingOffset + 4);
  if ((flags & 0x1) == 0) return null;
  final frameCount = _readUint32BE(bytes, xingOffset + 8);
  if (frameCount <= 0 || frame.sampleRate <= 0) return null;
  return _durationFromSeconds(
    frameCount * frame.samplesPerFrame / frame.sampleRate,
  );
}

Future<Duration?> _estimateWavDuration(File file, int length) async {
  final raf = await file.open();
  try {
    final header = await _readAt(raf, 0, math.min(12, length).toInt());
    if (!_asciiEquals(header, 0, 'RIFF') || !_asciiEquals(header, 8, 'WAVE')) {
      return null;
    }
    var offset = 12;
    int? byteRate;
    int? dataBytes;
    while (offset + 8 <= length) {
      final chunkHeader = await _readAt(raf, offset, 8);
      if (chunkHeader.length < 8) break;
      final type = String.fromCharCodes(chunkHeader.sublist(0, 4));
      final chunkSize = _readUint32LE(chunkHeader, 4);
      final contentOffset = offset + 8;
      if (type == 'fmt ' && chunkSize >= 16) {
        final fmt = await _readAt(raf, contentOffset, 16);
        if (fmt.length >= 12) {
          byteRate = _readUint32LE(fmt, 8);
        }
      } else if (type == 'data') {
        dataBytes = math.min(chunkSize, math.max(0, length - contentOffset));
      }
      if (byteRate != null && byteRate > 0 && dataBytes != null) {
        return _durationFromSeconds(dataBytes * 1.0 / byteRate);
      }
      final nextOffset = contentOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
      if (nextOffset <= offset) break;
      offset = nextOffset;
    }
    return null;
  } finally {
    await raf.close();
  }
}

Future<Duration?> _estimateMp4Duration(File file, int length) async {
  final raf = await file.open();
  try {
    return _findMp4DurationInRange(raf, 0, length, depth: 0);
  } finally {
    await raf.close();
  }
}

Future<Duration?> _findMp4DurationInRange(
  RandomAccessFile raf,
  int start,
  int end, {
  required int depth,
}) async {
  if (depth > 3) return null;
  var offset = start;
  while (offset + 8 <= end) {
    final box = await _readMp4BoxHeader(raf, offset, end);
    if (box == null || box.size <= box.headerSize) break;
    final contentStart = offset + box.headerSize;
    final boxEnd = math.min(offset + box.size, end);
    if (box.type == 'mvhd') {
      return _readMvhdDuration(raf, contentStart, boxEnd);
    }
    if (box.type == 'moov') {
      final duration = await _findMp4DurationInRange(
        raf,
        contentStart,
        boxEnd,
        depth: depth + 1,
      );
      if (duration != null) return duration;
    }
    if (boxEnd <= offset) break;
    offset = boxEnd;
  }
  return null;
}

Future<_Mp4Box?> _readMp4BoxHeader(
  RandomAccessFile raf,
  int offset,
  int end,
) async {
  final header = await _readAt(raf, offset, 8);
  if (header.length < 8) return null;
  final smallSize = _readUint32BE(header, 0);
  final type = String.fromCharCodes(header.sublist(4, 8));
  var headerSize = 8;
  var size = smallSize;
  if (smallSize == 1) {
    final large = await _readAt(raf, offset + 8, 8);
    if (large.length < 8) return null;
    size = _readUint64BE(large, 0);
    headerSize = 16;
  } else if (smallSize == 0) {
    size = end - offset;
  }
  if (size <= 0 || offset + size > end) return null;
  return _Mp4Box(type: type, size: size, headerSize: headerSize);
}

Future<Duration?> _readMvhdDuration(
  RandomAccessFile raf,
  int contentStart,
  int boxEnd,
) async {
  final header = await _readAt(
    raf,
    contentStart,
    math.min(32, boxEnd - contentStart).toInt(),
  );
  if (header.length < 20) return null;
  final version = header[0];
  if (version == 1) {
    if (header.length < 32) return null;
    final timescale = _readUint32BE(header, 20);
    final durationUnits = _readUint64BE(header, 24);
    if (timescale <= 0 || durationUnits <= 0) return null;
    return _durationFromSeconds(durationUnits / timescale);
  }
  final timescale = _readUint32BE(header, 12);
  final durationUnits = _readUint32BE(header, 16);
  if (timescale <= 0 || durationUnits <= 0) return null;
  return _durationFromSeconds(durationUnits / timescale);
}

Future<Uint8List> _readAt(RandomAccessFile raf, int offset, int count) async {
  if (count <= 0) return Uint8List(0);
  await raf.setPosition(offset);
  return raf.read(count);
}

Duration? _durationFromSeconds(num seconds) {
  final value = seconds.toDouble();
  if (!value.isFinite || value <= 0) return null;
  return Duration(milliseconds: (value * 1000).round());
}

bool _asciiEquals(Uint8List bytes, int offset, String value) {
  if (offset < 0 || offset + value.length > bytes.length) return false;
  for (var i = 0; i < value.length; i++) {
    if (bytes[offset + i] != value.codeUnitAt(i)) return false;
  }
  return true;
}

int? _readSynchsafeUint32(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 4 > bytes.length) return null;
  final b0 = bytes[offset];
  final b1 = bytes[offset + 1];
  final b2 = bytes[offset + 2];
  final b3 = bytes[offset + 3];
  if ((b0 | b1 | b2 | b3) & 0x80 != 0) return null;
  return (b0 << 21) | (b1 << 14) | (b2 << 7) | b3;
}

int _readUint32BE(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

int _readUint64BE(Uint8List bytes, int offset) {
  return (_readUint32BE(bytes, offset) << 32) |
      _readUint32BE(bytes, offset + 4);
}

int _readUint32LE(Uint8List bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

class _Mp3Frame {
  const _Mp3Frame({
    required this.versionBits,
    required this.layer,
    required this.bitrate,
    required this.sampleRate,
    required this.samplesPerFrame,
    required this.channelMode,
  });

  final int versionBits;
  final int layer;
  final int bitrate;
  final int sampleRate;
  final int samplesPerFrame;
  final int channelMode;
}

class _Mp4Box {
  const _Mp4Box({
    required this.type,
    required this.size,
    required this.headerSize,
  });

  final String type;
  final int size;
  final int headerSize;
}

Duration _clampDuration(Duration value, Duration max) {
  if (value < Duration.zero) return Duration.zero;
  if (max > Duration.zero && value > max) return max;
  return value;
}

Duration _durationDistance(Duration a, Duration b) {
  final delta = a - b;
  return delta.isNegative ? -delta : delta;
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
