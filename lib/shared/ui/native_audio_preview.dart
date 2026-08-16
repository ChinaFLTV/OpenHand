import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:openhand/shared/ui/openhand_spacing.dart';
import 'package:path/path.dart' as p;

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../net/http_redirect_utils.dart';
import '../util/async_concurrency.dart';
import '../util/bounded_file_io.dart';
import '../util/byte_size_format.dart';
import '../util/date_time_format.dart';
import '../util/input_value_parsing.dart';
import '../util/serial_task_queue.dart';
import '../util/text_normalization.dart';
import '../util/timer_safety.dart';
import 'animated_menu.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';

const Duration kNativeAudioLoadTimeout = Duration(seconds: 18);
const Duration kNativeAudioControlTimeout = Duration(seconds: 8);
const Duration kNativeAudioSeekStep = Duration(seconds: 15);
const Curve kNativeAudioMotionCurve = Cubic(0.22, 1.22, 0.36, 1);
const Size kNativeAudioPreviewPreferredSize = Size(640, 560);
const Duration _kNativeAudioPollInterval = Duration(milliseconds: 250);
const Duration _kNativeAudioMetadataPollTimeout = Duration(milliseconds: 450);
const Duration _kNativeAudioDurationProbeInterval = Duration(milliseconds: 180);
const Duration _kNativeAudioCompletionTolerance = Duration(seconds: 2);
const Duration _kNativeAudioSeekSettleDelay = Duration(milliseconds: 90);
const Duration _kNativeAudioSeekTolerance = Duration(milliseconds: 900);
const Duration _kNativeAudioPostSeekReportGuard = Duration(milliseconds: 1400);
const int _kNativeAudioDurationProbeAttempts = 8;
const int _kNativeAudioSeekConfirmAttempts = 2;
const int _kNativeAudioHeaderProbeBytes = 256 * kBytesPerKiB;
const double _kNativeAudioWideBreakpoint = 540;
const double _kNativeAudioShortBreakpoint = 430;

void _logNativeAudioStreamError(
  String streamName,
  Object error,
  StackTrace stack,
) {
  silentLog('native_audio_preview', '读取$streamName流', error, stack);
}

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
  standard(Icons.tune_rounded, 1.0),
  spatial(Icons.view_in_ar_rounded, 1.0),
  vocal(Icons.record_voice_over_rounded, 1.0),
  warm(Icons.graphic_eq_rounded, 0.96);

  const _NativeAudioEffect(this.icon, this.volumeScale);

  final IconData icon;
  final double volumeScale;
}

String _nativeAudioEffectLabel(
  AppLocalizations l10n,
  _NativeAudioEffect effect,
) {
  return switch (effect) {
    _NativeAudioEffect.standard => l10n.nativeAudioEffectStandard,
    _NativeAudioEffect.spatial => l10n.nativeAudioEffectSpatial,
    _NativeAudioEffect.vocal => l10n.nativeAudioEffectVocal,
    _NativeAudioEffect.warm => l10n.nativeAudioEffectWarm,
  };
}

bool _nativeAudioPreviewSourcesReferToSameMedia(
  NativeAudioPreviewSource a,
  NativeAudioPreviewSource b,
) {
  if (a.filePath != b.filePath ||
      a.networkUrl != b.networkUrl ||
      a.mimeType != b.mimeType) {
    return false;
  }
  return _sameNativeAudioBytes(a.bytes, b.bytes);
}

enum _NativeAudioPlaybackState { stopped, paused, playing, completed }

class _NativeAudioResolvedSource {
  const _NativeAudioResolvedSource({
    this.filePath,
    this.networkUrl,
    this.bytes,
    this.mimeType,
  });

  final String? filePath;
  final String? networkUrl;
  final Uint8List? bytes;
  final String? mimeType;
}

abstract class _NativeAudioPlaybackEngine {
  Stream<_NativeAudioPlaybackState> get stateStream;

  Stream<Duration> get positionStream;

  Stream<Duration> get durationStream;

  Future<Duration?> setSource(_NativeAudioResolvedSource source);

  Future<Duration?> getDuration();

  Future<Duration?> getCurrentPosition();

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position);

  Future<void> setVolume(double volume);

  Future<void> dispose();
}

_NativeAudioPlaybackEngine _createNativeAudioPlaybackEngine() {
  return _MediaKitPlaybackEngine();
}

class _MediaKitPlaybackEngine implements _NativeAudioPlaybackEngine {
  _MediaKitPlaybackEngine() {
    mk.MediaKit.ensureInitialized();
    _player = mk.Player();
    _subscriptions
      ..add(
        _player.stream.playing.listen(
          (playing) {
            _playing = playing;
            if (!_completed) _emitState();
          },
          onError: (Object error, StackTrace stack) {
            _logNativeAudioStreamError('播放状态', error, stack);
          },
        ),
      )
      ..add(
        _player.stream.completed.listen(
          (completed) {
            _completed = completed;
            _emitState();
          },
          onError: (Object error, StackTrace stack) {
            _logNativeAudioStreamError('播放完成状态', error, stack);
          },
        ),
      )
      ..add(
        _player.stream.error.listen(
          (message) {
            silentLog('native_audio_preview', 'media_kit 播放错误', message);
          },
          onError: (Object error, StackTrace stack) {
            _logNativeAudioStreamError('播放器错误', error, stack);
          },
        ),
      );
  }

  late final mk.Player _player;
  final StreamController<_NativeAudioPlaybackState> _stateController =
      StreamController<_NativeAudioPlaybackState>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  bool _playing = false;
  bool _completed = false;

  @override
  Stream<_NativeAudioPlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Future<Duration?> setSource(_NativeAudioResolvedSource source) async {
    _completed = false;
    _playing = false;
    final media = await _toMedia(source);
    await _player.open(media, play: false);
    _emitState();
    return _player.state.duration > Duration.zero
        ? _player.state.duration
        : null;
  }

  Future<mk.Media> _toMedia(_NativeAudioResolvedSource source) async {
    final bytes = source.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return mk.Media.memory(bytes, type: source.mimeType);
    }
    final filePath = source.filePath;
    if (filePath != null && filePath.trim().isNotEmpty) {
      return mk.Media(filePath);
    }
    final networkUrl = source.networkUrl;
    if (networkUrl != null && networkUrl.trim().isNotEmpty) {
      return mk.Media(networkUrl.trim());
    }
    throw const FileSystemException('音频源不可用。');
  }

  @override
  Future<Duration?> getDuration() async {
    final duration = _player.state.duration;
    return duration > Duration.zero ? duration : null;
  }

  @override
  Future<Duration?> getCurrentPosition() async => _player.state.position;

  @override
  Future<void> play() async {
    _completed = false;
    await _player.play();
    _playing = true;
    _emitState();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _playing = false;
    _emitState();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _playing = false;
    _completed = false;
    _emitState();
  }

  @override
  Future<void> seek(Duration position) async {
    _completed = false;
    await _player.seek(position);
    _emitState();
  }

  @override
  Future<void> setVolume(double volume) {
    return _player.setVolume((volume * 100).clamp(0.0, 100.0));
  }

  @override
  Future<void> dispose() async {
    await Future.wait<bool>(
      _subscriptions.map(
        (subscription) => cancelStreamSubscriptionBounded<dynamic>(
          subscription,
          onError: (error, stack) =>
              silentLog('native_audio_preview', '取消播放引擎订阅', error, stack),
        ),
      ),
    );
    await runAsyncCleanupBounded(
      _stateController.close,
      timeout: kNativeAudioControlTimeout,
      onError: (error, stack) =>
          silentLog('native_audio_preview', '关闭播放状态流', error, stack),
    );
    await runAsyncCleanupBounded(
      _player.dispose,
      timeout: kNativeAudioControlTimeout,
      onError: (error, stack) =>
          silentLog('native_audio_preview', '释放媒体播放器', error, stack),
    );
  }

  void _emitState() {
    if (_stateController.isClosed) return;
    final state = _completed
        ? _NativeAudioPlaybackState.completed
        : _playing
        ? _NativeAudioPlaybackState.playing
        : _NativeAudioPlaybackState.paused;
    _stateController.add(state);
  }
}

class _NativeAudioPreviewState extends State<NativeAudioPreview> {
  final _NativeAudioPlaybackEngine _player = _createNativeAudioPlaybackEngine();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  _NativeAudioPlayMode _playMode = _NativeAudioPlayMode.sequence;
  _NativeAudioEffect _effect = _NativeAudioEffect.standard;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  _NativeAudioPlaybackState _playerState = _NativeAudioPlaybackState.stopped;
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
  int _seekSerial = 0;
  bool _handlingComplete = false;
  final LatestTaskQueue _bootstrapQueue = LatestTaskQueue();
  final LatestTaskQueue _seekCommandQueue = LatestTaskQueue();
  final Stopwatch _seekGuardStopwatch = Stopwatch()..start();
  Duration? _recentSeekTarget;
  Duration? _recentSeekAt;

  bool get _isActive => !_disposed && mounted;
  bool get _isPlaying => _playerState == _NativeAudioPlaybackState.playing;
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
        _player.stateStream.listen(
          (state) {
            if (!mounted) return;
            if (state == _NativeAudioPlaybackState.completed) {
              if (_seeking ||
                  _manualProgressActive ||
                  !_isNearAudioEnd(_position)) {
                return;
              }
              setState(() {
                _playerState = state;
                if (_duration > Duration.zero) _position = _duration;
              });
              unawaited(_handleComplete());
              return;
            }
            if (_seeking) return;
            setState(() => _playerState = state);
          },
          onError: (Object error, StackTrace stack) {
            _logNativeAudioStreamError('预览状态', error, stack);
          },
        ),
      )
      ..add(
        _player.durationStream.listen(
          (duration) {
            if (!mounted || duration < Duration.zero) return;
            _setKnownDuration(duration);
          },
          onError: (Object error, StackTrace stack) {
            _logNativeAudioStreamError('音频时长', error, stack);
          },
        ),
      )
      ..add(
        _player.positionStream.listen(
          (position) {
            if (!mounted ||
                _seeking ||
                _manualProgressActive ||
                position < Duration.zero) {
              return;
            }
            _setKnownPosition(position);
          },
          onError: (Object error, StackTrace stack) {
            _logNativeAudioStreamError('播放位置', error, stack);
          },
        ),
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
    if (!_nativeAudioPreviewSourcesReferToSameMedia(
      oldWidget.source,
      widget.source,
    )) {
      unawaited(_bootstrap());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _bootstrapSerial++;
    _seekSerial++;
    _bootstrapQueue.discardPending();
    _seekCommandQueue.discardPending();
    _progressPollTimer?.cancel();
    if (widget.controller?._state == this) widget.controller?._state = null;
    for (final subscription in _subscriptions) {
      unawaited(
        cancelStreamSubscriptionBounded<dynamic>(
          subscription,
          onError: (error, stack) =>
              silentLog('native_audio_preview', '取消预览订阅', error, stack),
        ),
      );
    }
    unawaited(_disposePlayerAndTemp());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_disposed) return;
    final serial = ++_bootstrapSerial;
    final source = widget.source;
    _seekSerial++;
    _seekCommandQueue.discardPending();
    setState(() {
      _loading = true;
      _sourceReady = false;
      _loadError = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _seeking = false;
      _manualProgressActive = false;
      _handlingComplete = false;
      _recentSeekTarget = null;
      _recentSeekAt = null;
    });

    await _bootstrapQueue.enqueue(
      () => _runBootstrap(serial: serial, source: source),
    );
  }

  Future<void> _runBootstrap({
    required int serial,
    required NativeAudioPreviewSource source,
  }) async {
    if (!_isBootstrapActive(serial)) return;
    try {
      await _stopForSourceReset();
      if (!_isBootstrapActive(serial)) return;
      await _deleteTempAudioFile();
      if (!_isBootstrapActive(serial)) return;
      await _player
          .setVolume(_effectiveVolume)
          .timeout(kNativeAudioControlTimeout);
      if (!_isBootstrapActive(serial)) return;
      final resolvedSource = await _resolveAudioSource(source, serial: serial);
      if (!_isBootstrapActive(serial)) return;
      final loadedDuration = await _player
          .setSource(resolvedSource)
          .timeout(kNativeAudioLoadTimeout);
      if (!_isBootstrapActive(serial)) return;
      final duration = loadedDuration != null && loadedDuration > Duration.zero
          ? loadedDuration
          : await _resolveBestDuration(source, serial: serial);
      if (!_isBootstrapActive(serial)) return;
      setState(() {
        _duration = duration;
        _loading = false;
        _sourceReady = true;
        _loadError = null;
      });
      _restartProgressPolling();
      if (duration <= Duration.zero) {
        unawaited(_refreshDurationWhenAvailable(serial, source));
      }
      unawaited(_pollPlaybackState());
      if (widget.autoplay) {
        await _play(
          bootstrapSerial: serial,
        ).timeout(kNativeAudioControlTimeout);
      }
    } on TimeoutException catch (error, stack) {
      _handleLoadFailure(error, stack, serial);
    } catch (error, stack) {
      _handleLoadFailure(error, stack, serial);
    }
  }

  bool _isBootstrapActive(int serial) {
    return _isActive && serial == _bootstrapSerial;
  }

  Future<Duration> _resolveDuration(int serial) async {
    final initial = await _player.getDuration().timeout(
      _kNativeAudioMetadataPollTimeout,
      onTimeout: () => null,
    );
    if (!_isBootstrapActive(serial)) return Duration.zero;
    if (initial != null && initial > Duration.zero) return initial;
    for (
      var attempt = 0;
      attempt < _kNativeAudioDurationProbeAttempts;
      attempt++
    ) {
      final stillActive = await delayWhileContinuing(
        _kNativeAudioDurationProbeInterval,
        () => _isBootstrapActive(serial),
      );
      if (!stillActive) return Duration.zero;
      final next = await _player.getDuration().timeout(
        _kNativeAudioMetadataPollTimeout,
        onTimeout: () => null,
      );
      if (!_isBootstrapActive(serial)) return Duration.zero;
      if (next != null && next > Duration.zero) return next;
    }
    return Duration.zero;
  }

  Future<Duration> _resolveBestDuration(
    NativeAudioPreviewSource source, {
    required int serial,
  }) async {
    final localDuration = await _resolveLocalDurationHint(source);
    if (!_isBootstrapActive(serial)) return Duration.zero;
    if (localDuration != null && localDuration > Duration.zero) {
      return localDuration;
    }
    return _resolveDuration(serial);
  }

  Future<void> _refreshDurationWhenAvailable(
    int serial,
    NativeAudioPreviewSource source,
  ) async {
    try {
      final duration = await _resolveBestDuration(source, serial: serial);
      if (!_isBootstrapActive(serial) || duration <= Duration.zero) {
        return;
      }
      _setKnownDuration(duration);
    } catch (error, stack) {
      silentLog('native_audio_preview', '刷新音频时长', error, stack);
    }
  }

  Future<Duration?> _resolveLocalDurationHint(
    NativeAudioPreviewSource source,
  ) async {
    if (kIsWeb) return null;
    final path = nullIfBlank(source.filePath) ?? nullIfBlank(_tempAudioPath);
    if (path == null) return null;
    try {
      return await estimateNativeAudioFileDuration(path, source.mimeType);
    } catch (error, stack) {
      silentLog('native_audio_preview', '解析本地音频时长', error, stack);
      return null;
    }
  }

  void _restartProgressPolling() {
    if (!_isActive) return;
    _progressPollTimer?.cancel();
    _progressPollTimer = startNonOverlappingPeriodicTimer(
      _kNativeAudioPollInterval,
      (_) => _pollPlaybackState(),
    );
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
      silentLog('native_audio_preview', '轮询播放状态失败', error, stack);
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
    final clamped = _clampDuration(reported, duration);
    if (_isStalePostSeekReport(clamped)) return null;
    return clamped;
  }

  bool _isStalePostSeekReport(Duration reported) {
    final target = _recentSeekTarget;
    final committedAt = _recentSeekAt;
    if (target == null || committedAt == null) return false;
    final elapsed = _seekGuardStopwatch.elapsed - committedAt;
    if (elapsed > _kNativeAudioPostSeekReportGuard) {
      _recentSeekTarget = null;
      _recentSeekAt = null;
      return false;
    }
    final allowedDrift = _kNativeAudioSeekTolerance + elapsed;
    return _durationDistance(reported, target) > allowedDrift;
  }

  bool _isNearAudioEnd(Duration value) {
    if (_duration <= Duration.zero) return true;
    return value + _kNativeAudioCompletionTolerance >= _duration;
  }

  Future<_NativeAudioResolvedSource> _resolveAudioSource(
    NativeAudioPreviewSource source, {
    required int serial,
  }) async {
    final mimeType = source.mimeType;
    final filePath = source.filePath;
    if (filePath != null && filePath.trim().isNotEmpty) {
      return _resolveLocalAudioSource(filePath, mimeType: mimeType);
    }
    final url = source.networkUrl;
    if (url != null && url.trim().isNotEmpty) {
      final uri = Uri.tryParse(url.trim());
      final scheme = uri?.scheme.toLowerCase();
      if (uri == null ||
          (scheme != 'http' && scheme != 'https' && scheme != 'file')) {
        throw FormatException('不支持的音频地址：$url');
      }
      if (scheme == 'file') {
        return _resolveLocalAudioSource(uri.toFilePath(), mimeType: mimeType);
      }
      return _NativeAudioResolvedSource(
        networkUrl: url.trim(),
        mimeType: mimeType,
      );
    }
    final bytes = source.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      if (!kIsWeb) {
        final ext = _extensionForAudioMime(source.mimeType);
        final file = File(
          '${Directory.systemTemp.path}/openhand-audio-${DateTime.now().microsecondsSinceEpoch}.$ext',
        );
        await writeTemporaryFileBytesBounded(
          file,
          bytes,
          timeout: kNativeAudioControlTimeout,
          onSecondaryError: (error, stack) =>
              silentLog('native_audio_preview', '清理音频临时文件', error, stack),
        );
        if (_isBootstrapActive(serial)) {
          _tempAudioPath = file.path;
        } else {
          await _deleteAudioTempFile(file.path);
        }
        return _NativeAudioResolvedSource(
          filePath: file.path,
          mimeType: mimeType,
        );
      }
      return _NativeAudioResolvedSource(bytes: bytes, mimeType: mimeType);
    }
    throw const FileSystemException('音频源不可用。');
  }

  Future<_NativeAudioResolvedSource> _resolveLocalAudioSource(
    String filePath, {
    String? mimeType,
  }) async {
    if (!await isRegularFilePath(
      filePath,
      timeout: kNativeAudioControlTimeout,
      followLinks: true,
    )) {
      throw FileSystemException('音频源文件不存在。', filePath);
    }
    return _NativeAudioResolvedSource(filePath: filePath, mimeType: mimeType);
  }

  void _handleLoadFailure(Object error, StackTrace stack, int serial) {
    silentLog('native_audio_preview', '加载音频源失败', error, stack);
    if (_disposed || !mounted || serial != _bootstrapSerial) return;
    setState(() {
      _loading = false;
      _sourceReady = false;
      _loadError = AppLocalizations.of(context)!.nativeAudioLoadFailed;
    });
  }

  Future<void> _handleComplete() async {
    if (!_isActive || _handlingComplete || !_sourceReady) return;
    _handlingComplete = true;
    try {
      switch (_playMode) {
        case _NativeAudioPlayMode.repeatOne:
          if (!await _seekTo(Duration.zero)) return;
          await _play();
        case _NativeAudioPlayMode.shuffle:
          final dur = _duration;
          final maxMs = math.max(0, dur.inMilliseconds - 1000);
          final offset = maxMs > 0 ? math.Random().nextInt(maxMs) : 0;
          if (!await _seekTo(Duration(milliseconds: offset))) return;
          await _play();
        case _NativeAudioPlayMode.sequence:
          await _player.pause().timeout(kNativeAudioControlTimeout);
          if (!await _seekTo(Duration.zero)) return;
          if (mounted) {
            setState(() => _playerState = _NativeAudioPlaybackState.completed);
          }
      }
    } catch (error, stack) {
      silentLog('native_audio_preview', '处理播放完成状态', error, stack);
    } finally {
      _handlingComplete = false;
    }
  }

  Future<void> _togglePlayPause() async {
    if (!_isActive || _operationInFlight || _seeking) return;
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
      silentLog('native_audio_preview', '切换播放状态失败', error, stack);
      if (_isActive) {
        setState(() {
          _loadError = AppLocalizations.of(context)!.nativeAudioPlaybackFailed;
        });
      }
    } finally {
      _operationInFlight = false;
    }
  }

  Future<void> _play({int? bootstrapSerial}) async {
    bool isActive() =>
        _isActive &&
        (bootstrapSerial == null || bootstrapSerial == _bootstrapSerial);

    if (!_sourceReady || !isActive()) return;
    if (_playerState == _NativeAudioPlaybackState.completed &&
        _isNearAudioEnd(_position)) {
      if (!await _seekTo(Duration.zero)) return;
      if (!isActive()) return;
    }
    await _applyEffectToPlayer();
    if (!isActive()) return;
    await _player.play();
    if (isActive()) _restartProgressPolling();
  }

  Future<void> _seekBy(Duration delta) async {
    await _seekTo(_position + delta);
  }

  Future<bool> _seekTo(Duration target) async {
    if (!_isActive || !_sourceReady) return false;
    final seekSerial = ++_seekSerial;
    final shouldResumeAfterSeek = _isPlaying;
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
      if (_playerState == _NativeAudioPlaybackState.completed &&
          !_isNearAudioEnd(clamped)) {
        _playerState = _NativeAudioPlaybackState.paused;
      }
    });
    final executed = await _seekCommandQueue.enqueue(
      () => _performSeekTo(seekSerial, clamped, shouldResumeAfterSeek),
    );
    return executed && _isCurrentSeek(seekSerial);
  }

  Future<void> _performSeekTo(
    int seekSerial,
    Duration clamped,
    bool shouldResumeAfterSeek,
  ) async {
    if (!_isCurrentSeek(seekSerial)) return;
    var seekCommandCompleted = false;
    try {
      await _player.seek(clamped).timeout(kNativeAudioControlTimeout);
      if (!_isCurrentSeek(seekSerial)) return;
      await _confirmSeekPosition(seekSerial, clamped);
      if (!_isCurrentSeek(seekSerial)) return;
      if (shouldResumeAfterSeek && _isCurrentSeek(seekSerial)) {
        await _applyEffectToPlayer();
        await _player.play().timeout(kNativeAudioControlTimeout);
      }
      seekCommandCompleted = true;
      if (_isCurrentSeek(seekSerial)) {
        _rememberRecentSeek(clamped);
        setState(() {
          _seeking = false;
          _position = _clampDuration(clamped, _duration);
          if (shouldResumeAfterSeek) {
            _playerState = _NativeAudioPlaybackState.playing;
          }
        });
        _restartProgressPolling();
        unawaited(_pollPlaybackState());
      }
    } catch (error, stack) {
      silentLog('native_audio_preview', '定位播放位置失败', error, stack);
    } finally {
      if (!seekCommandCompleted && _isCurrentSeek(seekSerial)) {
        setState(() {
          _seeking = false;
          _position = _clampDuration(clamped, _duration);
        });
        _restartProgressPolling();
      }
    }
  }

  Future<void> _confirmSeekPosition(int seekSerial, Duration target) async {
    if (target <= Duration.zero) return;
    for (
      var attempt = 0;
      attempt < _kNativeAudioSeekConfirmAttempts;
      attempt++
    ) {
      final stillActive = await delayWhileContinuing(
        _kNativeAudioSeekSettleDelay,
        () => _isCurrentSeek(seekSerial),
      );
      if (!stillActive) return;
      final actual = await _player.getCurrentPosition().timeout(
        _kNativeAudioMetadataPollTimeout,
        onTimeout: () => null,
      );
      if (actual == null || _isCloseToSeekTarget(actual, target)) return;
      await _player.seek(target).timeout(kNativeAudioControlTimeout);
    }
  }

  bool _isCloseToSeekTarget(Duration actual, Duration target) {
    if (_duration > Duration.zero &&
        _isNearAudioEnd(actual) &&
        _isNearAudioEnd(target)) {
      return true;
    }
    return _durationDistance(actual, target) <= _kNativeAudioSeekTolerance;
  }

  void _rememberRecentSeek(Duration target) {
    _recentSeekTarget = target;
    _recentSeekAt = _seekGuardStopwatch.elapsed;
  }

  bool _isCurrentSeek(int seekSerial) {
    return _isActive && seekSerial == _seekSerial;
  }

  Future<void> _setVolume(double value) async {
    final next = finiteUnitInterval(value);
    setState(() {
      _volume = next;
      _muted = next <= 0;
    });
    try {
      await _player
          .setVolume(_effectiveVolume)
          .timeout(kNativeAudioControlTimeout);
    } catch (error, stack) {
      silentLog('native_audio_preview', '设置音量失败', error, stack);
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
      silentLog('native_audio_preview', '切换静音状态失败', error, stack);
    }
  }

  Future<void> _setEffect(_NativeAudioEffect effect) async {
    if (!_isActive) return;
    setState(() => _effect = effect);
    try {
      await _applyEffectToPlayer().timeout(kNativeAudioControlTimeout);
    } catch (error, stack) {
      silentLog('native_audio_preview', '应用音效失败', error, stack);
    }
  }

  Future<void> _applyEffectToPlayer() async {
    try {
      await _player
          .setVolume(_effectiveVolume)
          .timeout(kNativeAudioControlTimeout);
    } catch (error, stack) {
      silentLog('native_audio_preview', '设置音效音量失败', error, stack);
    }
  }

  double get _effectiveVolume =>
      _muted ? 0.0 : finiteUnitInterval(_volume * _effect.volumeScale);

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
    final motionDur = openHandMotionDuration(context, widget.motionDuration);
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
                    switchOutCurve: kOpenHandSwitchInCurve,
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
                // 加载遮罩淡入淡出：直接挂上/摘掉会让整块封面区闪一下。
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_loading,
                    child: AnimatedOpacity(
                      opacity: _loading ? 1 : 0,
                      duration: openHandMotionDuration(
                        context,
                        kOpenHandMotion200,
                      ),
                      curve: kOpenHandSwitchInCurve,
                      child: ColoredBox(
                        color: colorScheme.surface.withValues(alpha: 0.60),
                        child: Center(
                          // 只停用转圈自身的 ticker，不能包裹 AnimatedOpacity。
                          child: TickerMode(
                            enabled: _loading,
                            child: CircularProgressIndicator(
                              color: colorScheme.primary,
                              strokeWidth: 2.6,
                            ),
                          ),
                        ),
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
        kOpenHandGap3,
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
    final progress = unitRatio(
      _position.inMilliseconds,
      _duration.inMilliseconds,
    );
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
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _NativeAudioIconButton(
          tooltip: l10n.nativeAudioBack15Seconds,
          icon: Icons.replay_10_rounded,
          onPressed: _sourceReady
              ? () => unawaited(_seekBy(-kNativeAudioSeekStep))
              : null,
        ),
        kOpenHandHGap12,
        _NativeAudioIconButton(
          tooltip: _isPlaying ? l10n.nativeAudioPause : l10n.nativeAudioPlay,
          icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          prominent: true,
          onPressed: _sourceReady ? () => unawaited(_togglePlayPause()) : null,
        ),
        kOpenHandHGap12,
        _NativeAudioIconButton(
          tooltip: l10n.nativeAudioForward15Seconds,
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
    final l10n = AppLocalizations.of(context)!;
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
              tooltip: _muted ? l10n.nativeAudioUnmute : l10n.nativeAudioMute,
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
            ),
          ],
        );
      },
    );
  }

  Widget _buildError(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return ColoredBox(
      color: cs.surface.withValues(alpha: 0.76),
      child: Center(
        child: ConstrainedBox(
          constraints: kOpenHandContentMaxWidth360,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kOpenHandRadius16),
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, color: cs.error, size: 30),
                  kOpenHandGap10,
                  Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  kOpenHandGap14,
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => unawaited(_bootstrap()),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(l10n.commonRetry),
                      ),
                      if (widget.onOpenExternal != null)
                        FilledButton.icon(
                          onPressed: widget.onOpenExternal,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: Text(l10n.nativeAudioSystemPlayer),
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
    final l10n = AppLocalizations.of(context)!;
    return switch (_playMode) {
      _NativeAudioPlayMode.sequence => l10n.nativeAudioSequencePlayback,
      _NativeAudioPlayMode.repeatOne => l10n.nativeAudioRepeatOne,
      _NativeAudioPlayMode.shuffle => l10n.nativeAudioShufflePlayback,
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
    await _deleteAudioTempFile(path);
  }

  Future<void> _deleteAudioTempFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists().timeout(kNativeAudioControlTimeout)) {
        await file.delete().timeout(kNativeAudioControlTimeout);
      }
    } catch (error, stack) {
      silentLog('native_audio_preview', '删除临时音频失败', error, stack);
    }
  }

  Future<void> _stopForSourceReset() async {
    try {
      await _player.stop().timeout(kNativeAudioControlTimeout);
    } catch (error, stack) {
      silentLog('native_audio_preview', '重置前停止播放器失败', error, stack);
    }
  }

  Future<void> _disposePlayerAndTemp() async {
    try {
      await runAsyncCleanupBounded(
        () => Future.wait<void>(<Future<void>>[
          _bootstrapQueue.idle,
          _seekCommandQueue.idle,
        ]),
        timeout: kNativeAudioControlTimeout,
        onError: (error, stack) =>
            silentLog('native_audio_preview', '等待播放器操作结束', error, stack),
      );
      await _player.dispose();
    } catch (error, stack) {
      silentLog('native_audio_preview', '释放播放器失败', error, stack);
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
  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: kOpenHandMotion2200,
  );

  @override
  void didUpdateWidget(covariant _NativeAudioAlbumCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncGlowController(openHandTickerMotionEnabled(context));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncGlowController(openHandTickerMotionEnabled(context));
  }

  void _syncGlowController(bool motionEnabled) {
    if (widget.isPlaying && motionEnabled) {
      if (_glowController.isAnimating) return;
      _glowController.repeat(reverse: true);
      return;
    }
    _glowController.stop();
  }

  @override
  void dispose() {
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
    final motionEnabled = openHandTickerMotionEnabled(context);
    _syncGlowController(motionEnabled);
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final breath = widget.isPlaying && motionEnabled
            ? kOpenHandEmphasizedTransitionCurve.transform(_glowController.value)
            : 0.0;
        final playLift = widget.isPlaying && motionEnabled ? 1.0 : 0.0;
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
  void didUpdateWidget(covariant _NativeAudioAnimatedBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(openHandTickerMotionEnabled(context));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController(openHandTickerMotionEnabled(context));
  }

  void _syncController(bool motionEnabled) {
    if (widget.duration > Duration.zero && motionEnabled) {
      if (_controller.isAnimating) return;
      _controller.repeat(reverse: true);
      return;
    }
    _controller.stop();
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
    final motionEnabled = openHandTickerMotionEnabled(context);
    _syncController(motionEnabled);
    final animateBackdrop = widget.duration > Duration.zero && motionEnabled;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = animateBackdrop
            ? widget.curve.transform(_controller.value)
            : 0.0;
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
        duration: openHandMotionDuration(
          context,
          const Duration(milliseconds: 140),
        ),
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
  });

  final _NativeAudioEffect effect;
  final ValueChanged<_NativeAudioEffect> onSelect;

  @override
  Widget build(BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    final l10n = AppLocalizations.of(ctx)!;
    final label = _nativeAudioEffectLabel(l10n, effect);
    return Tooltip(
      message: l10n.nativeAudioEffectTooltip(label),
      child: InkWell(
        borderRadius: BorderRadius.circular(kOpenHandRadius20),
        onTap: () => _showMenu(ctx, l10n, cs),
        child: AnimatedContainer(
          duration: openHandMotionDuration(
            ctx,
            kOpenHandMotion160,
          ),
          curve: kNativeAudioMotionCurve,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: effect != _NativeAudioEffect.standard
                ? cs.primary.withValues(alpha: 0.12)
                : cs.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(kOpenHandRadius20),
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
              kOpenHandHGap5,
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
              kOpenHandHGap3,
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

  void _showMenu(BuildContext ctx, AppLocalizations l10n, ColorScheme cs) {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    showAnimatedMenu<_NativeAudioEffect>(
      context: ctx,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy - _NativeAudioEffect.values.length * 44.0 - 8,
        offset.dx + size.width,
        offset.dy,
      ),
      items: _NativeAudioEffect.values.map((e) {
        final eLabel = _nativeAudioEffectLabel(l10n, e);
        return PopupMenuItem<_NativeAudioEffect>(
          value: e,
          child: Row(
            children: [
              Icon(
                e.icon,
                size: 18,
                color: e == effect ? cs.primary : cs.onSurfaceVariant,
              ),
              kOpenHandHGap10,
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
      if (!ctx.mounted || selected == null) return;
      onSelect(selected);
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
      .replaceAll(kInlineWhitespacePattern, ' ')
      .replaceAll(
        RegExp(r'\.(mp3|wav|m4a|aac|ogg|opus|flac)$', caseSensitive: false),
        '',
      )
      .trim();
}

String deriveNativeAudioArtist(String detail) {
  final leaf = _prettyNativeAudioLeaf(detail);
  final segments = splitTrimmedNonEmpty(leaf, separator: RegExp(r'[-_]+'));
  if (segments.length >= 2 && segments.first.length <= 28) {
    return segments.first;
  }
  if (looksLikeGeneratedNativeAudioName(leaf)) {
    return 'AI 音频';
  }
  return 'OpenHand 音频';
}

String deriveNativeAudioAlbum(String detail) {
  final leaf = _prettyNativeAudioLeaf(detail);
  if (looksLikeGeneratedNativeAudioName(leaf)) {
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
    return lastSegment;
  }
  return p.basename(value.replaceAll('\\', '/'));
}

String _prettyNativeAudioLeaf(String detail) {
  final leaf = normalizeNativeAudioText(
    lastNativeAudioPathOrUrlSegment(detail),
    fallback: detail,
  );
  if (looksLikeGeneratedNativeAudioName(leaf)) {
    return '生成音频';
  }
  return leaf;
}

bool looksLikeGeneratedNativeAudioName(String value) {
  final normalized = value.trim().toLowerCase();
  return RegExp(r'^audio[_-]?\d+$').hasMatch(normalized) ||
      RegExp(r'^audio[_-]').hasMatch(normalized);
}

bool _sameNativeAudioBytes(Uint8List? a, Uint8List? b) {
  return listEquals<int>(a, b);
}

String _formatNativeAudioTime(Duration value) {
  if (value <= Duration.zero) return '00:00';
  final total = value.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  return hours > 0
      ? '$hours:${twoDigit(minutes)}:${twoDigit(seconds)}'
      : '${twoDigit(minutes)}:${twoDigit(seconds)}';
}

Future<Duration?> estimateNativeAudioFileDuration(
  String filePath,
  String? mimeType,
) async {
  final file = File(filePath);
  final deadline = MonotonicDeadline(
    kNativeAudioControlTimeout,
    timeoutMessage: '音频时长探测超过总时限。',
  );
  BoundedRandomAccessFileLease? input;
  try {
    final initialStat = await file.stat().timeout(deadline.remaining());
    if (!isRegularFileStat(initialStat) || initialStat.size <= 0) return null;
    final openedInput = await openBoundedRandomAccessFileLease(
      file,
      mode: FileMode.read,
      timeout: deadline.remaining(),
    );
    input = openedInput;
    final length = await openedInput.run<int>(
      (activeFile) => activeFile.length(),
      timeout: deadline.remaining(),
    );
    if (length != initialStat.size) return null;

    final normalizedMime = mimeType?.split(';').first.trim().toLowerCase();
    final extension = p.extension(filePath).toLowerCase();
    final kind = _nativeAudioContainerKind(extension, normalizedMime);
    var duration = kind == null
        ? null
        : await _estimateNativeAudioDurationByKind(
            openedInput,
            length,
            kind,
            deadline,
          );
    duration ??= await _estimateNativeAudioDurationBySniffing(
      openedInput,
      length,
      deadline,
    );

    final finalLength = await openedInput.run<int>(
      (activeFile) => activeFile.length(),
      timeout: deadline.remaining(),
    );
    final finalStat = await file.stat().timeout(deadline.remaining());
    if (!isRegularFileStat(finalStat) ||
        finalLength != length ||
        finalStat.size != initialStat.size ||
        finalStat.modified != initialStat.modified ||
        finalStat.changed != initialStat.changed) {
      return null;
    }
    await openedInput.close(timeout: deadline.remaining());
    input = null;
    return duration;
  } finally {
    deadline.stop();
    await input?.cleanup();
  }
}

String? _nativeAudioContainerKind(String extension, String? mimeType) {
  if (mimeType == kAudioMpegMimeType ||
      mimeType == kAudioMp3AliasMimeType ||
      extension == '.mp3') {
    return 'mp3';
  }
  if (mimeType == kAudioWavMimeType ||
      mimeType == kAudioWaveAliasMimeType ||
      mimeType == kAudioXWavAliasMimeType ||
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
  BoundedRandomAccessFileLease input,
  int length,
  String kind,
  MonotonicDeadline deadline,
) {
  return switch (kind) {
    'mp3' => _estimateMp3Duration(input, length, deadline),
    'wav' => _estimateWavDuration(input, length, deadline),
    'mp4' => _estimateMp4Duration(input, length, deadline),
    _ => Future<Duration?>.value(),
  };
}

Future<Duration?> _estimateNativeAudioDurationBySniffing(
  BoundedRandomAccessFileLease input,
  int length,
  MonotonicDeadline deadline,
) async {
  final header = await _readAt(
    input,
    0,
    math.min(16, length).toInt(),
    deadline,
  );
  if (_asciiEquals(header, 0, 'ID3') ||
      (header.length >= 2 && header[0] == 0xFF && (header[1] & 0xE0) == 0xE0)) {
    return _estimateMp3Duration(input, length, deadline);
  }
  if (_asciiEquals(header, 0, 'RIFF') && _asciiEquals(header, 8, 'WAVE')) {
    return _estimateWavDuration(input, length, deadline);
  }
  if (_asciiEquals(header, 4, 'ftyp')) {
    return _estimateMp4Duration(input, length, deadline);
  }
  return null;
}

Future<Duration?> _estimateMp3Duration(
  BoundedRandomAccessFileLease input,
  int length,
  MonotonicDeadline deadline,
) async {
  final probe = await _readAt(
    input,
    0,
    math.min(_kNativeAudioHeaderProbeBytes, length).toInt(),
    deadline,
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
    final tail = await _readAt(input, length - 128, 128, deadline);
    if (_asciiEquals(tail, 0, 'TAG')) {
      audioBytes = math.max(0, audioBytes - 128);
    }
  }
  if (audioBytes <= 0 || frame.bitrate <= 0) return null;
  return _durationFromSeconds((audioBytes * 8) / frame.bitrate);
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

Future<Duration?> _estimateWavDuration(
  BoundedRandomAccessFileLease input,
  int length,
  MonotonicDeadline deadline,
) async {
  final header = await _readAt(
    input,
    0,
    math.min(12, length).toInt(),
    deadline,
  );
  if (!_asciiEquals(header, 0, 'RIFF') || !_asciiEquals(header, 8, 'WAVE')) {
    return null;
  }
  var offset = 12;
  int? byteRate;
  int? dataBytes;
  while (offset + 8 <= length) {
    final chunkHeader = await _readAt(input, offset, 8, deadline);
    if (chunkHeader.length < 8) break;
    final type = String.fromCharCodes(chunkHeader.sublist(0, 4));
    final chunkSize = _readUint32LE(chunkHeader, 4);
    final contentOffset = offset + 8;
    if (type == 'fmt ' && chunkSize >= 16) {
      final fmt = await _readAt(input, contentOffset, 16, deadline);
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
}

Future<Duration?> _estimateMp4Duration(
  BoundedRandomAccessFileLease input,
  int length,
  MonotonicDeadline deadline,
) {
  return _findMp4DurationInRange(
    input,
    0,
    length,
    depth: 0,
    deadline: deadline,
  );
}

Future<Duration?> _findMp4DurationInRange(
  BoundedRandomAccessFileLease input,
  int start,
  int end, {
  required int depth,
  required MonotonicDeadline deadline,
}) async {
  if (depth > 3) return null;
  var offset = start;
  while (offset + 8 <= end) {
    final box = await _readMp4BoxHeader(input, offset, end, deadline);
    if (box == null || box.size <= box.headerSize) break;
    final contentStart = offset + box.headerSize;
    final boxEnd = math.min(offset + box.size, end);
    if (box.type == 'mvhd') {
      return _readMvhdDuration(input, contentStart, boxEnd, deadline);
    }
    if (box.type == 'moov') {
      final duration = await _findMp4DurationInRange(
        input,
        contentStart,
        boxEnd,
        depth: depth + 1,
        deadline: deadline,
      );
      if (duration != null) return duration;
    }
    if (boxEnd <= offset) break;
    offset = boxEnd;
  }
  return null;
}

Future<_Mp4Box?> _readMp4BoxHeader(
  BoundedRandomAccessFileLease input,
  int offset,
  int end,
  MonotonicDeadline deadline,
) async {
  final header = await _readAt(input, offset, 8, deadline);
  if (header.length < 8) return null;
  final smallSize = _readUint32BE(header, 0);
  final type = String.fromCharCodes(header.sublist(4, 8));
  var headerSize = 8;
  var size = smallSize;
  if (smallSize == 1) {
    final large = await _readAt(input, offset + 8, 8, deadline);
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
  BoundedRandomAccessFileLease input,
  int contentStart,
  int boxEnd,
  MonotonicDeadline deadline,
) async {
  final header = await _readAt(
    input,
    contentStart,
    math.min(32, boxEnd - contentStart).toInt(),
    deadline,
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

Future<Uint8List> _readAt(
  BoundedRandomAccessFileLease input,
  int offset,
  int count,
  MonotonicDeadline deadline,
) async {
  if (count <= 0) return Uint8List(0);
  return input.run<Uint8List>((activeFile) async {
    await activeFile.setPosition(offset);
    return activeFile.read(count);
  }, timeout: deadline.remaining());
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
  return a >= b ? a - b : b - a;
}

String _extensionForAudioMime(String? mimeType) {
  return switch (mimeType?.toLowerCase()) {
    kAudioWavMimeType || kAudioWaveAliasMimeType || kAudioXWavAliasMimeType => 'wav',
    'audio/mp4' || 'audio/m4a' || 'audio/x-m4a' => 'm4a',
    kAudioAacMimeType => 'aac',
    kAudioOggMimeType || 'audio/opus' => 'ogg',
    kAudioFlacMimeType || 'audio/x-flac' => 'flac',
    _ => 'mp3',
  };
}
