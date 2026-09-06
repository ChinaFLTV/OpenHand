import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/timer_safety.dart';
import '../../model/ai_model_config.dart';
import '../../model/offline_speech_model.dart';
import '../chat/ai_chat_service.dart';
import 'ai_speech_text_polishing_service.dart';
import 'offline_speech_model_service.dart';

enum AiVoiceConversationPhase {
  idle,
  starting,
  listening,
  recognizing,
  polishing,
  speaking,
  failed,
}

class AiVoiceConversationResumeState {
  const AiVoiceConversationResumeState({
    this.microphoneEnabled = true,
    this.speakerMuted = false,
    this.currentTranscript = '',
    this.previousTranscript = '',
  });

  factory AiVoiceConversationResumeState.fromSnapshot(
    AiVoiceConversationSnapshot snapshot,
  ) {
    return AiVoiceConversationResumeState(
      microphoneEnabled: snapshot.microphoneEnabled,
      speakerMuted: snapshot.speakerMuted,
      currentTranscript: snapshot.currentTranscript.trim(),
      previousTranscript: snapshot.previousTranscript.trim(),
    );
  }

  final bool microphoneEnabled;
  final bool speakerMuted;
  final String currentTranscript;
  final String previousTranscript;
}

class AiVoiceConversationSnapshot {
  const AiVoiceConversationSnapshot({
    required this.active,
    required this.microphoneEnabled,
    required this.speakerMuted,
    required this.phase,
    required this.currentTranscript,
    required this.previousTranscript,
    required this.inputLevel,
    this.message,
  });

  const AiVoiceConversationSnapshot.idle()
    : active = false,
      microphoneEnabled = true,
      speakerMuted = false,
      phase = AiVoiceConversationPhase.idle,
      currentTranscript = '',
      previousTranscript = '',
      inputLevel = 0,
      message = null;

  AiVoiceConversationSnapshot.suspended(AiVoiceConversationResumeState state)
    : active = false,
      microphoneEnabled = state.microphoneEnabled,
      speakerMuted = state.speakerMuted,
      phase = AiVoiceConversationPhase.idle,
      currentTranscript = state.currentTranscript,
      previousTranscript = state.previousTranscript,
      inputLevel = 0,
      message = null;

  final bool active;
  final bool microphoneEnabled;
  final bool speakerMuted;
  final AiVoiceConversationPhase phase;
  final String currentTranscript;
  final String previousTranscript;
  final double inputLevel;
  final String? message;

  AiVoiceConversationSnapshot copyWith({
    bool? active,
    bool? microphoneEnabled,
    bool? speakerMuted,
    AiVoiceConversationPhase? phase,
    String? currentTranscript,
    String? previousTranscript,
    double? inputLevel,
    String? message,
    bool clearMessage = false,
  }) {
    return AiVoiceConversationSnapshot(
      active: active ?? this.active,
      microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
      speakerMuted: speakerMuted ?? this.speakerMuted,
      phase: phase ?? this.phase,
      currentTranscript: currentTranscript ?? this.currentTranscript,
      previousTranscript: previousTranscript ?? this.previousTranscript,
      inputLevel: inputLevel ?? this.inputLevel,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class AiVoiceConversationService extends ChangeNotifier {
  AiVoiceConversationService({
    OfflineSpeechModelService? modelService,
    AiSpeechTextPolishingService? polishingService,
    AudioRecorder? recorder,
  }) : _modelService = modelService ?? OfflineSpeechModelService.instance,
       _polishingService = polishingService ?? AiSpeechTextPolishingService(),
       _ownsPolishingService = polishingService == null,
       _recorder = recorder ?? AudioRecorder(),
       _ownsRecorder = recorder == null;

  static const int _sampleRate = 16000;
  static const int _channelCount = 1;
  static const int _bytesPerSample = 2;
  static const int _preRollBytes = _sampleRate * _bytesPerSample ~/ 3;
  static const int _minimumRecognitionBytes =
      _sampleRate * _bytesPerSample * 3 ~/ 5;
  static const int _maximumUtteranceBytes = _sampleRate * _bytesPerSample * 120;
  static const double _minimumSpeechLevel = 0.0015;
  static const double _initialNoiseFloor = 0.0005;
  static const double _speechToNoiseRatio = 2.8;
  static const double _speechReleaseRatio = 1.7;
  static const double _minimumSpeechPeak = 0.008;
  static const double _minimumSpeechCrestFactor = 2.2;
  static const int _speechAttackChunks = 3;
  static const Duration _inputWatchdogTimeout = Duration(seconds: 5);
  static const Duration _partialRecognitionInterval = Duration(
    milliseconds: 950,
  );
  static const Duration _playbackTimeout = Duration(minutes: 1);
  static const Duration _realtimePlaybackTimeout = Duration(minutes: 5);
  static const Duration _playbackCompletionGrace = Duration(seconds: 15);
  static const int _initialSpeechChunkTerminalLimit = 8;
  static const int _initialSpeechChunkSoftLimit = 24;
  static const int _initialSpeechChunkHardLimit = 40;
  static const int _speechChunkTerminalLimit = 28;
  static const int _speechChunkSoftLimit = 64;
  static const int _speechChunkHardLimit = 104;
  static const int _speechAudioBufferLimit = 2;
  static const double _defaultSpeechVolume = 100;

  final OfflineSpeechModelService _modelService;
  final AiSpeechTextPolishingService _polishingService;
  final bool _ownsPolishingService;
  final AudioRecorder _recorder;
  final bool _ownsRecorder;

  AiVoiceConversationSnapshot _snapshot =
      const AiVoiceConversationSnapshot.idle();
  AiVoiceConversationSnapshot get snapshot => _snapshot;

  OfflineSpeechModelDefinition? _recognitionModel;
  OfflineSpeechModelDefinition? _synthesisModel;
  Map<String, Object?> _recognitionConfiguration = const <String, Object?>{};
  Map<String, Object?> _synthesisConfiguration = const <String, Object?>{};
  OfflineSpeechTextPolishingSettings _polishingSettings =
      const OfflineSpeechTextPolishingSettings.disabled();
  List<AiModelConfig> _availableModels = const <AiModelConfig>[];
  Duration _silenceTimeout = const Duration(seconds: 3);
  void Function(String text)? _onTextReady;
  void Function(String message)? _onIssue;
  bool _polishingUnavailable = false;
  final Set<String> _reportedIssues = <String>{};

  StreamSubscription<Uint8List>? _recordingSubscription;
  Timer? _silenceTimer;
  Timer? _partialRecognitionTimer;
  Timer? _inputWatchdogTimer;
  Completer<void>? _sessionCancellation;
  List<int> _preRoll = <int>[];
  List<int> _utterance = <int>[];
  bool _hasSpeech = false;
  int _speechCandidateChunks = 0;
  int _receivedAudioBytes = 0;
  double _noiseFloor = _initialNoiseFloor;
  double _maximumObservedLevel = 0;
  bool _inputWarningVisible = false;
  bool _partialRecognitionQueued = false;
  int _utteranceSerial = 0;
  int _sessionSerial = 0;
  int _lastPartialByteCount = 0;
  Future<void> _recognitionQueue = Future<void>.value();
  Completer<void>? _polishingCancellation;
  String _pendingPolishingText = '';
  int _polishingSerial = 0;
  bool _polishingWorkerActive = false;
  bool _restoredTranscriptPending = false;
  DateTime _lastLevelNotification = DateTime.fromMillisecondsSinceEpoch(0);

  mk.Player? _player;
  double _speechVolumeBeforeMute = _defaultSpeechVolume;
  final List<String> _speechQueue = <String>[];
  final List<({int serial, String path})> _speechAudioQueue =
      <({int serial, String path})>[];
  bool _speechGenerationActive = false;
  bool _speechPumpActive = false;
  int _speechSerial = 0;
  Completer<void> _speechCancellation = Completer<void>();
  String? _assistantMessageId;
  String _assistantText = '';
  int _assistantSpokenOffset = 0;
  bool _assistantResponseStreaming = false;
  bool _assistantSpeechBlocked = false;
  Completer<void>? _speechQueueWaiter;
  bool _disposed = false;

  Future<void> start({
    required OfflineSpeechSettings settings,
    required List<AiModelConfig> availableModels,
    required void Function(String text) onTextReady,
    required void Function(String message) onIssue,
    AiVoiceConversationResumeState resumeState =
        const AiVoiceConversationResumeState(),
  }) async {
    if (_disposed) throw StateError('语音沟通服务已关闭。');
    if (_snapshot.active) return;
    final recognition = _selectedModel(
      settings.recognition,
      OfflineSpeechKind.recognition,
    );
    if (recognition == null) throw StateError('请先在设置中启用一个语音识别模型。');
    final recognitionConfiguration = settings.recognition.configuration(
      recognition,
    );
    final availability = _modelService.availabilityFor(
      recognition,
      recognitionConfiguration,
    );
    if (!availability.available) throw StateError(availability.reason);
    if (!_modelService.isInstalled(recognition) ||
        _modelService.requiresDownloadForConfiguration(
          recognition,
          recognitionConfiguration,
        )) {
      throw StateError('语音识别模型尚未下载或运行环境尚未准备完成。');
    }
    if (!_modelService.isRuntimeReady(recognition)) {
      throw StateError('请先运行已启用的语音识别模型。');
    }
    if (!await _recorder.hasPermission()) throw StateError('没有麦克风权限。');
    final synthesis = _selectedModel(
      settings.synthesis,
      OfflineSpeechKind.synthesis,
    );
    if (synthesis == null) throw StateError('请先在设置中启用一个语音朗读模型。');
    final synthesisConfiguration = settings.synthesis.configuration(synthesis);
    final synthesisAvailability = _modelService.availabilityFor(
      synthesis,
      synthesisConfiguration,
    );
    if (!synthesisAvailability.available) {
      throw StateError(synthesisAvailability.reason);
    }
    if (!_modelService.isInstalled(synthesis) ||
        _modelService.requiresDownloadForConfiguration(
          synthesis,
          synthesisConfiguration,
        )) {
      throw StateError('语音朗读模型尚未下载或运行环境尚未准备完成。');
    }
    if (!_modelService.isRuntimeReady(synthesis)) {
      throw StateError('请先运行已启用的语音朗读模型。');
    }
    if (settings.textPolishing.enabled &&
        resolveSpeechTextPolishingModel(
              settings.textPolishing,
              availableModels,
            ) ==
            null) {
      throw StateError('文本润色已启用，请先选择一个可用的润色模型。');
    }

    _sessionSerial += 1;
    final sessionSerial = _sessionSerial;
    _sessionCancellation = Completer<void>();
    _recognitionModel = recognition;
    _recognitionConfiguration = recognitionConfiguration;
    _synthesisModel = synthesis;
    _synthesisConfiguration = synthesisConfiguration;
    _polishingSettings = settings.textPolishing;
    _availableModels = List<AiModelConfig>.unmodifiable(availableModels);
    _silenceTimeout = Duration(seconds: settings.silenceTimeoutSeconds);
    _onTextReady = onTextReady;
    _onIssue = onIssue;
    _polishingUnavailable = false;
    _pendingPolishingText = '';
    _polishingSerial += 1;
    _reportedIssues.clear();
    _restoredTranscriptPending = resumeState.currentTranscript
        .trim()
        .isNotEmpty;
    _snapshot = const AiVoiceConversationSnapshot.idle().copyWith(
      active: true,
      microphoneEnabled: resumeState.microphoneEnabled,
      speakerMuted: resumeState.speakerMuted,
      phase: AiVoiceConversationPhase.starting,
      currentTranscript: resumeState.currentTranscript.trim(),
      previousTranscript: resumeState.previousTranscript.trim(),
      clearMessage: true,
    );
    notifyListeners();

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: _channelCount,
        ),
      );
      if (!_isCurrentSession(sessionSerial)) {
        await _recorder.stop();
        return;
      }
      _recordingSubscription = stream.listen(
        (chunk) => _handleAudioChunk(sessionSerial, chunk),
        onError: (Object error, StackTrace stack) {
          silentLog('voice_conversation', '持续录音', error, stack);
          _fail('录音中断：$error');
        },
        onDone: () {
          if (_isCurrentSession(sessionSerial)) {
            _fail('麦克风音频流已中断，请重新开启语音沟通。');
          }
        },
      );
      if (!resumeState.microphoneEnabled) {
        await _recorder.pause();
        if (!_isCurrentSession(sessionSerial)) return;
      } else {
        _startInputWatchdog(sessionSerial);
      }
      _setSnapshot(
        _snapshot.copyWith(
          phase: AiVoiceConversationPhase.listening,
          clearMessage: true,
        ),
      );
    } catch (error, stack) {
      silentLog('voice_conversation', '启动语音沟通', error, stack);
      await _stopResources(markInactive: false);
      _setSnapshot(
        _snapshot.copyWith(
          active: false,
          phase: AiVoiceConversationPhase.failed,
          inputLevel: 0,
          message: '$error',
        ),
      );
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_snapshot.active && _snapshot.phase == AiVoiceConversationPhase.idle) {
      return;
    }
    _sessionSerial += 1;
    await _stopResources(markInactive: true);
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (!_snapshot.active || _snapshot.microphoneEnabled == enabled) return;
    final sessionSerial = _sessionSerial;
    if (enabled) {
      _setSnapshot(
        _snapshot.copyWith(
          microphoneEnabled: true,
          phase: AiVoiceConversationPhase.listening,
          clearMessage: true,
        ),
      );
      try {
        await _recorder.resume();
        if (!_isCurrentSession(sessionSerial)) return;
        _speechCandidateChunks = 0;
        _receivedAudioBytes = 0;
        _noiseFloor = _initialNoiseFloor;
        _maximumObservedLevel = 0;
        _inputWarningVisible = false;
        _startInputWatchdog(sessionSerial);
      } catch (error, stack) {
        if (!_isCurrentSession(sessionSerial)) return;
        silentLog('voice_conversation', '开启麦克风', error, stack);
        _setSnapshot(
          _snapshot.copyWith(microphoneEnabled: false, inputLevel: 0),
        );
        _notifyIssue('开启麦克风失败，请检查输入设备后重试。');
      }
    } else {
      _silenceTimer?.cancel();
      _partialRecognitionTimer?.cancel();
      _inputWatchdogTimer?.cancel();
      _setSnapshot(_snapshot.copyWith(microphoneEnabled: false, inputLevel: 0));
      try {
        await _recorder.pause();
        if (!_isCurrentSession(sessionSerial)) return;
        if (_hasSpeech) _finalizeUtterance(force: true);
      } catch (error, stack) {
        if (!_isCurrentSession(sessionSerial)) return;
        silentLog('voice_conversation', '关闭麦克风', error, stack);
        _setSnapshot(_snapshot.copyWith(microphoneEnabled: true));
        _startInputWatchdog(sessionSerial);
        _notifyIssue('关闭麦克风失败，请重试。');
      }
    }
  }

  Future<void> setSpeakerMuted(bool muted) async {
    if (!_snapshot.active || _snapshot.speakerMuted == muted) return;
    final previousMuted = _snapshot.speakerMuted;
    final player = _player;
    if (muted && player != null && player.state.volume > 0) {
      _speechVolumeBeforeMute = player.state.volume.clamp(
        0.0,
        _defaultSpeechVolume,
      );
    }
    _setSnapshot(_snapshot.copyWith(speakerMuted: muted));
    if (player == null) return;
    try {
      await player.setVolume(muted ? 0 : _speechVolumeBeforeMute);
      if (_snapshot.speakerMuted != muted) {
        await player.setVolume(
          _snapshot.speakerMuted ? 0 : _speechVolumeBeforeMute,
        );
      }
    } catch (error, stack) {
      silentLog('voice_conversation', '切换语音朗读静音状态', error, stack);
      if (_snapshot.speakerMuted == muted) {
        _setSnapshot(_snapshot.copyWith(speakerMuted: previousMuted));
        _notifyIssue('切换语音朗读静音状态失败，请重试。');
      }
    }
  }

  Future<void> forceSend() async {
    if (!_snapshot.active) return;
    if (_hasSpeech) {
      _finalizeUtterance(force: true);
      return;
    }
    final current = _snapshot.currentTranscript.trim();
    if (current.isEmpty) return;
    _restoredTranscriptPending = false;
    _setSnapshot(
      _snapshot.copyWith(currentTranscript: '', previousTranscript: current),
    );
    _queueRecognizedText(current, _sessionSerial);
  }

  void acknowledgeSubmittedText(String text) {
    final submitted = text.trim();
    if (!_snapshot.active || submitted.isEmpty) return;
    if (_snapshot.previousTranscript.trim() != submitted) return;
    _setSnapshot(_snapshot.copyWith(previousTranscript: ''));
  }

  void ingestAssistantResponse({
    required String messageId,
    required String text,
    required bool streaming,
  }) {
    if (!_snapshot.active) return;
    if (_assistantMessageId != messageId) {
      _assistantMessageId = messageId;
      _assistantText = '';
      _assistantSpokenOffset = 0;
      _assistantSpeechBlocked = false;
      _speechQueue.clear();
      _speechSerial += 1;
      _resetSpeechCancellation();
      _discardBufferedSpeech();
      unawaited(_stopPlayerSafely());
    }
    _assistantText = text;
    _assistantResponseStreaming = streaming;
    _wakeSpeechQueue();
    if (_assistantSpeechBlocked) {
      _assistantSpokenOffset = text.length;
      return;
    }
    if (_assistantSpokenOffset > text.length) _assistantSpokenOffset = 0;
    final chunks = _extractCompletedSpeechChunks(
      text,
      start: _assistantSpokenOffset,
      flushRemainder: !streaming,
    );
    if (chunks.isEmpty) {
      _startBufferedSpeechIfReady(_sessionSerial, _speechSerial);
      return;
    }
    _assistantSpokenOffset = chunks.last.$2;
    _speechQueue.addAll(chunks.map((entry) => entry.$1));
    _wakeSpeechQueue();
    unawaited(_generateSpeech(_sessionSerial, _speechSerial));
    _startBufferedSpeechIfReady(_sessionSerial, _speechSerial);
  }

  void interruptAssistantResponse() {
    if (!_snapshot.active) return;
    _assistantSpeechBlocked = true;
    _assistantSpokenOffset = _assistantText.length;
    _speechQueue.clear();
    _wakeSpeechQueue();
    _speechSerial += 1;
    _resetSpeechCancellation();
    _discardBufferedSpeech();
    unawaited(_stopPlayerSafely());
    if (_snapshot.phase == AiVoiceConversationPhase.speaking) {
      _setSnapshot(
        _snapshot.copyWith(phase: AiVoiceConversationPhase.listening),
      );
    }
  }

  OfflineSpeechModelDefinition? _selectedModel(
    OfflineSpeechModelSettings settings,
    OfflineSpeechKind kind,
  ) {
    final id = settings.enabledModelId;
    final model = id == null ? null : OfflineSpeechModelCatalog.byId(id);
    return model?.kind == kind ? model : null;
  }

  void _handleAudioChunk(int sessionSerial, Uint8List chunk) {
    if (!_isCurrentSession(sessionSerial) ||
        !_snapshot.microphoneEnabled ||
        _speechPumpActive ||
        _snapshot.phase == AiVoiceConversationPhase.speaking ||
        chunk.isEmpty) {
      return;
    }
    _receivedAudioBytes += chunk.length;
    final audio = _pcmMetrics(chunk);
    final level = audio.$1;
    _maximumObservedLevel = math.max(_maximumObservedLevel, level);
    if (_inputWarningVisible && level >= 1 / 32768) {
      _inputWarningVisible = false;
      _setSnapshot(_snapshot.copyWith(clearMessage: true));
    }
    final now = DateTime.now();
    if (now.difference(_lastLevelNotification) >=
        const Duration(milliseconds: 80)) {
      _lastLevelNotification = now;
      _setSnapshot(_snapshot.copyWith(inputLevel: _normalizeInputLevel(level)));
    }
    final voiced = _detectSpeech(level, audio.$2);
    if (!_hasSpeech) {
      _appendPreRoll(chunk);
      if (!voiced) return;
      if (_restoredTranscriptPending) {
        final restored = _snapshot.currentTranscript.trim();
        _restoredTranscriptPending = false;
        _setSnapshot(
          _snapshot.copyWith(
            currentTranscript: '',
            previousTranscript: restored.isEmpty
                ? _snapshot.previousTranscript
                : restored,
          ),
        );
      }
      _hasSpeech = true;
      _utterance.addAll(_preRoll);
      _preRoll.clear();
      _setSnapshot(_snapshot.copyWith(message: '检测到语音，正在实时识别…'));
    } else {
      _utterance.addAll(chunk);
    }
    if (voiced) {
      if (_silenceTimer != null) {
        _silenceTimer!.cancel();
        _silenceTimer = null;
        _setSnapshot(_snapshot.copyWith(message: '检测到语音，正在实时识别…'));
      }
    } else if (_silenceTimer == null) {
      _setSnapshot(
        _snapshot.copyWith(
          message: '检测到停顿，持续 ${_silenceTimeout.inSeconds} 秒后自动发送…',
        ),
      );
      _silenceTimer = startSafeTimer(_silenceTimeout, () {
        _silenceTimer = null;
        _finalizeUtterance(force: false);
      });
    }
    if (_utterance.length >= _maximumUtteranceBytes) {
      _finalizeUtterance(force: true);
      return;
    }
    if (!(_recognitionModel?.isOnline ?? false) &&
        _utterance.length >= _minimumRecognitionBytes &&
        _partialRecognitionTimer == null) {
      _partialRecognitionTimer = startSafeTimer(
        _partialRecognitionInterval,
        _queuePartialRecognition,
      );
    }
  }

  bool _detectSpeech(double level, double peak) {
    final ratio = _hasSpeech ? _speechReleaseRatio : _speechToNoiseRatio;
    final threshold = math.max(_minimumSpeechLevel, _noiseFloor * ratio);
    final candidate =
        level >= threshold &&
        peak >=
            math.max(_minimumSpeechPeak, threshold * _minimumSpeechCrestFactor);
    if (_hasSpeech) return candidate;

    if (candidate) {
      _speechCandidateChunks += 1;
      return _speechCandidateChunks >= _speechAttackChunks;
    }
    _speechCandidateChunks = 0;
    if (level > 0) {
      final weight = level < _noiseFloor ? 0.14 : 0.025;
      _noiseFloor += (level - _noiseFloor) * weight;
    }
    return false;
  }

  void _startInputWatchdog(int sessionSerial) {
    _inputWatchdogTimer?.cancel();
    _inputWatchdogTimer = startSafeTimer(_inputWatchdogTimeout, () {
      _inputWatchdogTimer = null;
      if (!_isCurrentSession(sessionSerial) ||
          !_snapshot.microphoneEnabled ||
          _hasSpeech) {
        return;
      }
      if (_speechPumpActive ||
          _snapshot.phase == AiVoiceConversationPhase.speaking) {
        _startInputWatchdog(sessionSerial);
        return;
      }
      if (_receivedAudioBytes == 0) {
        _fail('未收到有效的麦克风声音，请检查系统输入设备、输入音量和麦克风权限。');
      } else if (_maximumObservedLevel < 1 / 32768) {
        _inputWarningVisible = true;
        _setSnapshot(_snapshot.copyWith(message: '尚未检测到麦克风声音，请检查输入设备和输入音量。'));
      }
    });
  }

  void _appendPreRoll(Uint8List chunk) {
    _preRoll.addAll(chunk);
    if (_preRoll.length > _preRollBytes) {
      _preRoll = _preRoll.sublist(_preRoll.length - _preRollBytes);
    }
  }

  void _queuePartialRecognition() {
    _partialRecognitionTimer = null;
    if (!_snapshot.active || !_hasSpeech || _partialRecognitionQueued) return;
    if (_utterance.length - _lastPartialByteCount < _minimumRecognitionBytes) {
      _partialRecognitionTimer = startSafeTimer(
        _partialRecognitionInterval,
        _queuePartialRecognition,
      );
      return;
    }
    final serial = _utteranceSerial;
    final bytes = Uint8List.fromList(_utterance);
    _lastPartialByteCount = bytes.length;
    _partialRecognitionQueued = true;
    _recognitionQueue = _recognitionQueue
        .catchError((Object _, StackTrace _) {})
        .then((_) async {
          try {
            final text = await _recognize(bytes, _sessionSerial);
            if (!_snapshot.active ||
                serial != _utteranceSerial ||
                !hasMeaningfulSpeechText(text)) {
              return;
            }
            final previous = _snapshot.currentTranscript.trim();
            _setSnapshot(
              _snapshot.copyWith(
                phase: AiVoiceConversationPhase.listening,
                previousTranscript: previous.isEmpty || previous == text
                    ? _snapshot.previousTranscript
                    : previous,
                currentTranscript: text,
                clearMessage: _silenceTimer == null,
              ),
            );
          } catch (error, stack) {
            if (_snapshot.active && !_isExpectedCancellation(error)) {
              silentLog('voice_conversation', '刷新实时识别文本', error, stack);
            }
          } finally {
            _partialRecognitionQueued = false;
            if (_snapshot.active && _hasSpeech) {
              _partialRecognitionTimer ??= startSafeTimer(
                _partialRecognitionInterval,
                _queuePartialRecognition,
              );
            }
          }
        });
  }

  void _finalizeUtterance({required bool force}) {
    if (!_snapshot.active || !_hasSpeech) return;
    _silenceTimer?.cancel();
    _partialRecognitionTimer?.cancel();
    _silenceTimer = null;
    _partialRecognitionTimer = null;
    final sessionSerial = _sessionSerial;
    final bytes = Uint8List.fromList(_utterance);
    final partialTranscript = _snapshot.currentTranscript.trim();
    final fallback = hasMeaningfulSpeechText(partialTranscript)
        ? partialTranscript
        : '';
    _utteranceSerial += 1;
    _utterance = <int>[];
    _preRoll = <int>[];
    _hasSpeech = false;
    _speechCandidateChunks = 0;
    _lastPartialByteCount = 0;
    _setSnapshot(
      _snapshot.copyWith(
        phase: AiVoiceConversationPhase.recognizing,
        currentTranscript: '',
        previousTranscript: fallback.isEmpty
            ? _snapshot.previousTranscript
            : fallback,
        inputLevel: 0,
        message: force ? '正在提交识别文本…' : '检测到停顿，正在整理文本…',
      ),
    );
    _recognitionQueue = _recognitionQueue
        .catchError((Object _, StackTrace _) {})
        .then((_) async {
          var text = fallback;
          var recognitionFailed = false;
          try {
            final recognized = await _recognize(bytes, sessionSerial);
            if (recognized.isNotEmpty) text = recognized;
          } catch (error, stack) {
            if (!_isExpectedCancellation(error)) {
              recognitionFailed = true;
              silentLog('voice_conversation', '完成语音识别', error, stack);
              if (text.isEmpty && _isCurrentSession(sessionSerial)) {
                _notifyIssue('语音识别失败，请检查识别模型后重试。');
              }
            }
          }
          if (text.isNotEmpty && _isCurrentSession(sessionSerial)) {
            _queueRecognizedText(text, sessionSerial);
          } else if (_isCurrentSession(sessionSerial)) {
            final polishingPending = _pendingPolishingText.isNotEmpty;
            _setSnapshot(
              _snapshot.copyWith(
                phase: polishingPending
                    ? AiVoiceConversationPhase.polishing
                    : AiVoiceConversationPhase.listening,
                currentTranscript: polishingPending ? '' : null,
                previousTranscript: polishingPending
                    ? _pendingPolishingText
                    : null,
                clearMessage: !recognitionFailed && !polishingPending,
              ),
            );
          }
        })
        .catchError((Object error, StackTrace stack) {
          if (_isCurrentSession(sessionSerial) &&
              !_isExpectedCancellation(error)) {
            silentLog('voice_conversation', '提交语音识别文本', error, stack);
            _notifyIssue('提交识别文本失败，请重试。');
          }
        });
  }

  Future<String> _recognize(Uint8List pcm, int sessionSerial) async {
    if (!_isCurrentSession(sessionSerial)) return '';
    final model = _recognitionModel;
    if (model == null || pcm.length < _minimumRecognitionBytes) return '';
    _setSnapshot(
      _snapshot.copyWith(phase: AiVoiceConversationPhase.recognizing),
    );
    final directory = await Directory.systemTemp.createTemp(
      'openhand_voice_input_',
    );
    final path = p.join(directory.path, 'speech.wav');
    try {
      await File(path).writeAsBytes(_wavBytes(pcm), flush: true);
      final result = await _modelService.test(
        model,
        _recognitionConfiguration,
        audioPath: path,
        cancelSignal: _sessionCancellation?.future,
        startIfNeeded: false,
      );
      return result.transcript?.trim() ?? '';
    } finally {
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
      } catch (_) {}
    }
  }

  void _queueRecognizedText(String source, int sessionSerial) {
    final text = source.trim();
    if (!_isCurrentSession(sessionSerial)) return;
    if (!hasMeaningfulSpeechText(text)) {
      if (_pendingPolishingText.isEmpty) {
        _ignoreRecognizedText(sessionSerial);
      } else {
        _setSnapshot(
          _snapshot.copyWith(
            currentTranscript: '',
            previousTranscript: _pendingPolishingText,
            phase: AiVoiceConversationPhase.polishing,
            message: '正在润色识别文本…',
          ),
        );
      }
      return;
    }

    if (!_polishingSettings.enabled || _polishingUnavailable) {
      _deliverRecognizedText(text, sessionSerial);
      return;
    }

    final pending = _pendingPolishingText.trim();
    _pendingPolishingText = pending.isEmpty ? text : '$pending\n$text';
    _polishingSerial += 1;
    final cancellation = _polishingCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _setSnapshot(
      _snapshot.copyWith(
        currentTranscript: '',
        previousTranscript: _pendingPolishingText,
        phase: AiVoiceConversationPhase.polishing,
        message: pending.isEmpty ? '正在润色识别文本…' : '检测到新内容，正在重新润色…',
      ),
    );
    _startPolishingWorker();
  }

  void _startPolishingWorker() {
    if (_polishingWorkerActive || _pendingPolishingText.isEmpty) return;
    _polishingWorkerActive = true;
    final sessionSerial = _sessionSerial;
    unawaited(_runPolishingWorker(sessionSerial));
  }

  Future<void> _runPolishingWorker(int sessionSerial) async {
    try {
      while (_isCurrentSession(sessionSerial) &&
          _pendingPolishingText.isNotEmpty) {
        final polishingSerial = _polishingSerial;
        final source = _pendingPolishingText;
        final cancellation = Completer<void>();
        _polishingCancellation = cancellation;
        var text = source;
        var interrupted = false;
        final cancelSignal = combineCancelSignals(<Future<void>?>[
          _sessionCancellation?.future,
          cancellation.future,
        ]);
        try {
          text = await _polishingService.polish(
            text: source,
            settings: _polishingSettings,
            availableModels: _availableModels,
            cancelSignal: cancelSignal,
          );
        } catch (error, stack) {
          interrupted =
              cancellation.isCompleted ||
              polishingSerial != _polishingSerial ||
              _isExpectedCancellation(error);
          if (!interrupted) {
            final timedOut = _isPolishingTimeout(error);
            if (!timedOut) {
              silentLog('voice_conversation', '润色识别文本', error, stack);
            }
            if (!_isCurrentSession(sessionSerial)) return;
            _polishingUnavailable = !timedOut;
            _notifyIssue(_polishingFailureMessage(error));
          }
        } finally {
          if (identical(_polishingCancellation, cancellation)) {
            _polishingCancellation = null;
          }
          if (!cancellation.isCompleted) cancellation.complete();
        }

        if (interrupted ||
            !_isCurrentSession(sessionSerial) ||
            polishingSerial != _polishingSerial) {
          continue;
        }
        _pendingPolishingText = '';
        _deliverRecognizedText(text, sessionSerial);
      }
    } finally {
      _polishingWorkerActive = false;
      if (_isCurrentSession(_sessionSerial) &&
          _pendingPolishingText.isNotEmpty) {
        _startPolishingWorker();
      }
    }
  }

  void _deliverRecognizedText(String text, int sessionSerial) {
    if (!_isCurrentSession(sessionSerial)) return;
    if (!hasMeaningfulSpeechText(text)) {
      _ignoreRecognizedText(sessionSerial);
      return;
    }
    _pendingPolishingText = '';
    _setSnapshot(
      _snapshot.copyWith(
        currentTranscript: '',
        previousTranscript: text,
        phase: AiVoiceConversationPhase.listening,
        clearMessage: true,
      ),
    );
    _onTextReady?.call(text.trim());
  }

  void _cancelPolishing() {
    _polishingSerial += 1;
    final cancellation = _polishingCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _polishingCancellation = null;
    _pendingPolishingText = '';
  }

  void _ignoreRecognizedText(int sessionSerial) {
    if (!_isCurrentSession(sessionSerial)) return;
    _setSnapshot(
      _snapshot.copyWith(
        phase: AiVoiceConversationPhase.listening,
        currentTranscript: '',
        previousTranscript: '',
        inputLevel: 0,
        clearMessage: true,
      ),
    );
  }

  Future<void> _pumpSpeech(int sessionSerial, int speechSerial) async {
    if (_speechPumpActive) return;
    if (!_speechAudioQueue.any((audio) => audio.serial == speechSerial)) {
      return;
    }
    _speechPumpActive = true;
    try {
      while (_speechAudioQueue.any((audio) => audio.serial == speechSerial) &&
          _isCurrentSession(sessionSerial) &&
          speechSerial == _speechSerial) {
        final audioIndex = _speechAudioQueue.indexWhere(
          (audio) => audio.serial == speechSerial,
        );
        if (audioIndex == -1) break;
        final audioPath = _speechAudioQueue.removeAt(audioIndex).path;
        unawaited(_generateSpeech(sessionSerial, speechSerial));
        final playbackCancellation = _speechCancellation;
        StreamSubscription<bool>? playbackCompletionSubscription;
        StreamSubscription<String>? playbackErrorSubscription;
        try {
          if (!_isCurrentSession(sessionSerial) ||
              speechSerial != _speechSerial) {
            continue;
          }
          _setSnapshot(
            _snapshot.copyWith(
              phase: AiVoiceConversationPhase.speaking,
              clearMessage: true,
            ),
          );
          final player = _player ??= mk.Player();
          await player.open(mk.Media(audioPath), play: false);
          await player.setVolume(
            _snapshot.speakerMuted ? 0 : _speechVolumeBeforeMute,
          );
          if (playbackCancellation.isCompleted ||
              !_isCurrentSession(sessionSerial) ||
              speechSerial != _speechSerial) {
            continue;
          }
          final playbackCompleted = Completer<void>();
          playbackCompletionSubscription = player.stream.completed.listen(
            (completed) {
              if (completed && !playbackCompleted.isCompleted) {
                playbackCompleted.complete();
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!playbackCompleted.isCompleted) {
                playbackCompleted.completeError(error, stack);
              }
            },
            onDone: () {
              if (!playbackCompleted.isCompleted) {
                playbackCompleted.completeError(StateError('播放器完成事件流已关闭。'));
              }
            },
          );
          playbackErrorSubscription = player.stream.error.listen((message) {
            final detail = message.trim();
            if (detail.isNotEmpty && !playbackCompleted.isCompleted) {
              playbackCompleted.completeError(StateError(detail));
            }
          });
          await player.play();
          final duration = player.state.duration;
          final playbackDeadline = duration > Duration.zero
              ? duration + _playbackCompletionGrace
              : _playbackTimeout;
          await Future.any<void>(<Future<void>>[
            playbackCompleted.future,
            playbackCancellation.future,
          ]).timeout(playbackDeadline);
        } on TimeoutException catch (error, stack) {
          if (_isCurrentSession(sessionSerial)) {
            silentLog('voice_conversation', '等待朗读完成', error, stack);
            _blockAssistantSpeech('语音朗读超时，已停止本轮朗读。请检查朗读模型后重试。');
          }
        } catch (error, stack) {
          if (_isCurrentSession(sessionSerial) &&
              !_isExpectedCancellation(error)) {
            silentLog('voice_conversation', '朗读流式回复', error, stack);
            _blockAssistantSpeech('语音朗读失败，已停止本轮朗读。请检查朗读模型后重试。');
          }
        } finally {
          try {
            await playbackCompletionSubscription?.cancel();
          } catch (_) {}
          try {
            await playbackErrorSubscription?.cancel();
          } catch (_) {}
          await _deleteGeneratedAudio(audioPath);
        }
      }
    } finally {
      _speechPumpActive = false;
      if (_isCurrentSession(sessionSerial) &&
          _snapshot.phase == AiVoiceConversationPhase.speaking &&
          !_speechGenerationActive &&
          _speechQueue.isEmpty &&
          !_speechAudioQueue.any((audio) => audio.serial == speechSerial)) {
        _setSnapshot(
          _snapshot.copyWith(phase: AiVoiceConversationPhase.listening),
        );
      }
      if (_speechAudioQueue.any((audio) => audio.serial == _speechSerial) &&
          _snapshot.active) {
        unawaited(_pumpSpeech(_sessionSerial, _speechSerial));
      }
    }
  }

  Future<void> _generateSpeech(int sessionSerial, int speechSerial) async {
    if (_speechGenerationActive) return;
    _speechGenerationActive = true;
    try {
      final synthesisModel = _synthesisModel;
      if (synthesisModel != null &&
          _modelService.supportsRealtimeSynthesis(
            synthesisModel,
            _synthesisConfiguration,
          )) {
        await _streamSpeechResponse(sessionSerial, speechSerial);
        return;
      }
      while (_speechQueue.isNotEmpty &&
          _speechAudioQueue
                  .where((audio) => audio.serial == speechSerial)
                  .length <
              _speechAudioBufferLimit &&
          _isCurrentSession(sessionSerial) &&
          speechSerial == _speechSerial) {
        final audioPath = await _synthesizeSpeechChunk(
          _speechQueue.removeAt(0),
          sessionSerial,
          speechSerial,
        );
        if (audioPath == null) continue;
        if (!_isCurrentSession(sessionSerial) ||
            speechSerial != _speechSerial) {
          await _deleteGeneratedAudio(audioPath);
          continue;
        }
        _speechAudioQueue.add((serial: speechSerial, path: audioPath));
        _startBufferedSpeechIfReady(sessionSerial, speechSerial);
      }
    } finally {
      _speechGenerationActive = false;
      _startBufferedSpeechIfReady(_sessionSerial, _speechSerial);
      if (_speechQueue.isNotEmpty &&
          _speechAudioQueue
                  .where((audio) => audio.serial == _speechSerial)
                  .length <
              _speechAudioBufferLimit &&
          _snapshot.active) {
        unawaited(_generateSpeech(_sessionSerial, _speechSerial));
      }
    }
  }

  Future<void> _streamSpeechResponse(
    int sessionSerial,
    int speechSerial,
  ) async {
    final model = _synthesisModel;
    if (model == null || _speechQueue.isEmpty) return;
    final playbackCancellation = _speechCancellation;
    final cancelSignal = combineCancelSignals(<Future<void>?>[
      _sessionCancellation?.future,
      playbackCancellation.future,
    ]);
    OfflineSpeechAudioStream? speech;
    _StreamingPcmAudioSource? source;
    mk.Player? player;
    var realtimePlaybackConfigured = false;
    StreamSubscription<bool>? completionSubscription;
    StreamSubscription<String>? errorSubscription;
    try {
      if (!_modelService.isInstalled(model) ||
          _modelService.requiresDownloadForConfiguration(
            model,
            _synthesisConfiguration,
          ) ||
          !_modelService
              .availabilityFor(model, _synthesisConfiguration)
              .available) {
        _blockAssistantSpeech('语音朗读模型当前不可用，已停止本轮朗读。请检查模型配置。');
        return;
      }
      if (!_modelService.isRuntimeReady(model)) {
        _blockAssistantSpeech('语音朗读模型已停止运行，已停止本轮朗读。请重新启动模型。');
        return;
      }
      speech = await _modelService.startSynthesisStream(
        model,
        configuration: _synthesisConfiguration,
        cancelSignal: cancelSignal,
      );
      if (!_isCurrentSession(sessionSerial) || speechSerial != _speechSerial) {
        return;
      }
      source = await _StreamingPcmAudioSource.start(
        speech.audio,
        sampleRate: speech.sampleRate,
        channels: speech.channels,
      );
      final sourceFailure = Completer<void>();
      unawaited(
        source.done.then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (!sourceFailure.isCompleted) {
              sourceFailure.completeError(error, stack);
            }
          },
        ),
      );
      player = _player ??= mk.Player();
      realtimePlaybackConfigured = true;
      await _configureRealtimePlayback(
        player,
        sampleRate: speech.sampleRate,
        channels: speech.channels,
      );
      final completed = Completer<void>();
      completionSubscription = player.stream.completed.listen(
        (value) {
          if (value && !completed.isCompleted) completed.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!completed.isCompleted) completed.completeError(error, stack);
        },
        onDone: () {
          if (!completed.isCompleted) {
            completed.completeError(StateError('播放器完成事件流已关闭。'));
          }
        },
      );
      errorSubscription = player.stream.error.listen((message) {
        final detail = message.trim();
        if (detail.isNotEmpty && !completed.isCompleted) {
          completed.completeError(StateError(detail));
        }
      });
      _speechPumpActive = true;
      _setSnapshot(
        _snapshot.copyWith(
          phase: AiVoiceConversationPhase.speaking,
          clearMessage: true,
        ),
      );
      final feedFailure = Completer<void>();
      unawaited(
        _feedRealtimeSpeech(speech, sessionSerial, speechSerial).then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (!feedFailure.isCompleted) {
              feedFailure.completeError(error, stack);
            }
          },
        ),
      );
      await player.open(mk.Media(source.uri.toString()), play: false);
      await player.setVolume(
        _snapshot.speakerMuted ? 0 : _speechVolumeBeforeMute,
      );
      if (playbackCancellation.isCompleted ||
          !_isCurrentSession(sessionSerial) ||
          speechSerial != _speechSerial) {
        return;
      }
      await player.play();
      await Future.any<void>(<Future<void>>[
        completed.future,
        playbackCancellation.future,
        sourceFailure.future,
        feedFailure.future,
      ]).timeout(_realtimePlaybackTimeout);
    } on TimeoutException catch (error, stack) {
      if (_isCurrentSession(sessionSerial)) {
        silentLog('voice_conversation', '等待实时朗读完成', error, stack);
        _blockAssistantSpeech('语音朗读超时，已停止本轮朗读。请检查朗读模型后重试。');
      }
    } catch (error, stack) {
      if (_isCurrentSession(sessionSerial) && !_isExpectedCancellation(error)) {
        if (_isEmptySpeechAudioError(error)) {
          _notifyIssue('当前文本片段未生成语音，已跳过并继续处理后续内容。');
        } else {
          silentLog('voice_conversation', '生成实时回复语音', error, stack);
          _blockAssistantSpeech('实时语音生成失败，已停止本轮朗读。请检查朗读模型后重试。');
        }
      }
    } finally {
      try {
        await completionSubscription?.cancel();
      } catch (_) {}
      try {
        await errorSubscription?.cancel();
      } catch (_) {}
      if (realtimePlaybackConfigured && player != null) {
        await _stopPlayerSafely();
        await _restoreBufferedPlayback(player);
      }
      await speech?.close();
      await source?.close();
      _speechPumpActive = false;
      if (_isCurrentSession(sessionSerial) &&
          speechSerial == _speechSerial &&
          _snapshot.phase == AiVoiceConversationPhase.speaking) {
        _setSnapshot(
          _snapshot.copyWith(phase: AiVoiceConversationPhase.listening),
        );
      }
    }
  }

  Future<void> _feedRealtimeSpeech(
    OfflineSpeechAudioStream speech,
    int sessionSerial,
    int speechSerial,
  ) async {
    while (_isCurrentSession(sessionSerial) && speechSerial == _speechSerial) {
      while (_speechQueue.isNotEmpty) {
        final text = _speechQueue.removeAt(0);
        if (hasMeaningfulSpeechText(text)) speech.addText(text);
      }
      if (!_assistantResponseStreaming) {
        await speech.finish();
        return;
      }
      final waiter = Completer<void>();
      _speechQueueWaiter = waiter;
      if (_speechQueue.isNotEmpty || !_assistantResponseStreaming) {
        if (identical(_speechQueueWaiter, waiter)) {
          _speechQueueWaiter = null;
        }
        continue;
      }
      await Future.any<void>(<Future<void>>[
        waiter.future,
        _speechCancellation.future,
      ]);
      if (identical(_speechQueueWaiter, waiter)) {
        _speechQueueWaiter = null;
      }
    }
  }

  Future<void> _configureRealtimePlayback(
    mk.Player player, {
    required int sampleRate,
    required int channels,
  }) async {
    final platform = player.platform;
    if (kIsWeb || platform is! mk.NativePlayer) {
      throw StateError('当前平台不支持本地实时语音播放。');
    }
    final dynamic backend = platform;
    await backend.setProperty('demuxer-rawaudio-format', 's16le');
    await backend.setProperty('demuxer-rawaudio-rate', '$sampleRate');
    await backend.setProperty(
      'demuxer-rawaudio-channels',
      channels == 1
          ? 'mono'
          : channels == 2
          ? 'stereo'
          : '$channels',
    );
    await backend.setProperty('demuxer', 'rawaudio');
    await backend.setProperty('cache', 'no');
    await backend.setProperty('demuxer-readahead-secs', '0');
    await backend.setProperty('network-timeout', '60');
  }

  Future<void> _restoreBufferedPlayback(mk.Player player) async {
    final platform = player.platform;
    if (kIsWeb || platform is! mk.NativePlayer) return;
    try {
      final dynamic backend = platform;
      await backend.setProperty('demuxer', '');
      await backend.setProperty('cache', 'yes');
      await backend.setProperty('demuxer-readahead-secs', '1');
      await backend.setProperty('network-timeout', '5');
    } catch (error, stack) {
      silentLog('voice_conversation', '恢复普通语音播放参数', error, stack);
    }
  }

  void _startBufferedSpeechIfReady(int sessionSerial, int speechSerial) {
    if (_speechPumpActive ||
        !_isCurrentSession(sessionSerial) ||
        speechSerial != _speechSerial ||
        !_speechAudioQueue.any((audio) => audio.serial == speechSerial)) {
      return;
    }
    unawaited(_pumpSpeech(sessionSerial, speechSerial));
  }

  void _discardBufferedSpeech() {
    final discarded = List<({int serial, String path})>.from(_speechAudioQueue);
    _speechAudioQueue.clear();
    for (final audio in discarded) {
      unawaited(_deleteGeneratedAudio(audio.path));
    }
  }

  Future<String?> _synthesizeSpeechChunk(
    String text,
    int sessionSerial,
    int speechSerial,
  ) async {
    final model = _synthesisModel;
    if (model == null || !hasMeaningfulSpeechText(text)) return null;
    final speechCancellation = _speechCancellation.future;
    final cancelSignal = combineCancelSignals(<Future<void>?>[
      _sessionCancellation?.future,
      speechCancellation,
    ]);
    try {
      if (!_modelService.isInstalled(model) ||
          _modelService.requiresDownloadForConfiguration(
            model,
            _synthesisConfiguration,
          ) ||
          !_modelService
              .availabilityFor(model, _synthesisConfiguration)
              .available) {
        _blockAssistantSpeech('语音朗读模型当前不可用，已停止本轮朗读。请检查模型配置。');
        return null;
      }
      if (!_modelService.isRuntimeReady(model)) {
        _blockAssistantSpeech('语音朗读模型已停止运行，已停止本轮朗读。请重新启动模型。');
        return null;
      }
      if (!_isCurrentSession(sessionSerial) || speechSerial != _speechSerial) {
        return null;
      }
      final result = await _modelService.test(
        model,
        _synthesisConfiguration,
        sampleText: text,
        cancelSignal: cancelSignal,
        startIfNeeded: false,
      );
      final audioPath = result.audioPath?.trim();
      if (audioPath == null || audioPath.isEmpty) {
        _blockAssistantSpeech('语音朗读模型未生成有效音频，已停止本轮朗读。');
        return null;
      }
      return audioPath;
    } catch (error, stack) {
      if (_isCurrentSession(sessionSerial) && !_isExpectedCancellation(error)) {
        if (_isEmptySpeechAudioError(error)) {
          _notifyIssue('当前文本片段未生成语音，已跳过并继续处理后续内容。');
        } else {
          silentLog('voice_conversation', '生成流式回复语音', error, stack);
          _blockAssistantSpeech('语音生成失败，已停止本轮朗读。请检查朗读模型后重试。');
        }
      }
      return null;
    }
  }

  List<(String, int)> _extractCompletedSpeechChunks(
    String text, {
    required int start,
    required bool flushRemainder,
  }) {
    final result = <(String, int)>[];
    var segmentStart = start.clamp(0, text.length);
    for (var index = segmentStart; index < text.length; index += 1) {
      final character = text[index];
      final segmentLength = index - segmentStart + 1;
      final initialChunk = start == 0 && result.isEmpty;
      final terminalLimit = initialChunk
          ? _initialSpeechChunkTerminalLimit
          : _speechChunkTerminalLimit;
      final softLimit = initialChunk
          ? _initialSpeechChunkSoftLimit
          : _speechChunkSoftLimit;
      final hardLimit = initialChunk
          ? _initialSpeechChunkHardLimit
          : _speechChunkHardLimit;
      final englishSentenceEnd =
          character == '.' &&
          index + 1 < text.length &&
          ' \n\r\t'.contains(text[index + 1]);
      final terminalBoundary =
          segmentLength >= terminalLimit &&
          ('。！？!?；;\n'.contains(character) || englishSentenceEnd);
      final softBoundary =
          segmentLength >= softLimit && '，,、：: '.contains(character);
      final hardBoundary =
          segmentLength >= hardLimit &&
          (text.codeUnitAt(index) & 0xFC00) != 0xD800;
      if (!terminalBoundary && !softBoundary && !hardBoundary) {
        continue;
      }
      final chunk = _cleanSpeechText(text.substring(segmentStart, index + 1));
      if (hasMeaningfulSpeechText(chunk)) result.add((chunk, index + 1));
      segmentStart = index + 1;
    }
    if (flushRemainder && segmentStart < text.length) {
      final chunk = _cleanSpeechText(text.substring(segmentStart));
      if (hasMeaningfulSpeechText(chunk)) result.add((chunk, text.length));
    }
    return result;
  }

  String _cleanSpeechText(String source) {
    return source
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp('`([^`]*)`'), r'$1')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp('[#>*_~]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  (double, double) _pcmMetrics(Uint8List bytes) {
    if (bytes.length < 2) return (0, 0);
    var squareSum = 0.0;
    var peak = 0.0;
    var samples = 0;
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      var sample = bytes[index] | (bytes[index + 1] << 8);
      if (sample >= 0x8000) sample -= 0x10000;
      final normalized = sample / 32768;
      squareSum += normalized * normalized;
      peak = math.max(peak, normalized.abs());
      samples += 1;
    }
    return (math.sqrt(squareSum / samples).clamp(0, 1), peak.clamp(0, 1));
  }

  double _normalizeInputLevel(double level) {
    if (level <= 0) return 0;
    final decibels = 20 * math.log(level) / math.ln10;
    return ((decibels + 60) / 42).clamp(0, 1);
  }

  Uint8List _wavBytes(Uint8List pcm) {
    final output = Uint8List(44 + pcm.length);
    final data = ByteData.sublistView(output);
    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index += 1) {
        output[offset + index] = value.codeUnitAt(index);
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, _channelCount, Endian.little);
    data.setUint32(24, _sampleRate, Endian.little);
    data.setUint32(
      28,
      _sampleRate * _channelCount * _bytesPerSample,
      Endian.little,
    );
    data.setUint16(32, _channelCount * _bytesPerSample, Endian.little);
    data.setUint16(34, _bytesPerSample * 8, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, pcm.length, Endian.little);
    output.setRange(44, output.length, pcm);
    return output;
  }

  bool _isCurrentSession(int serial) {
    return !_disposed && _snapshot.active && serial == _sessionSerial;
  }

  bool _isExpectedCancellation(Object error) {
    return error is OfflineSpeechTestCancelled ||
        error is AiChatCancelledException;
  }

  bool _isPolishingTimeout(Object error) {
    if (error is TimeoutException) return true;
    final message = '$error'.toLowerCase();
    return message.contains('timeout') || message.contains('超时');
  }

  bool _isEmptySpeechAudioError(Object error) {
    final message = '$error';
    return message.contains('模型没有生成音频采样') ||
        message.contains('模型没有生成有效音频') ||
        message.contains('文本没有可朗读内容');
  }

  String _polishingFailureMessage(Object error) {
    if (_isPolishingTimeout(error)) {
      return '文本润色超时，已改用识别原文发送。后续内容仍会继续尝试润色。';
    }
    if (error is AiChatEmptyResponseException) {
      return '文本润色模型未返回有效内容，已改用识别原文发送。请更换润色模型。';
    }
    if (error is AiChatException) {
      return switch (error.statusCode) {
        401 => '文本润色模型鉴权失败，已改用识别原文发送。请检查密钥或更换模型。',
        403 => '文本润色模型无访问权限或受地区限制，已改用识别原文发送。请更换模型。',
        429 => '文本润色服务请求过于频繁或额度不足，已改用识别原文发送。',
        _ => '文本润色失败，已改用识别原文发送。请检查或更换润色模型。',
      };
    }
    return '文本润色失败，已改用识别原文发送。请检查或更换润色模型。';
  }

  void _notifyIssue(String message) {
    if (!_snapshot.active) return;
    _setSnapshot(_snapshot.copyWith(message: message));
    if (_reportedIssues.add(message)) _onIssue?.call(message);
  }

  void _blockAssistantSpeech(String message) {
    if (!_snapshot.active || _assistantSpeechBlocked) return;
    _assistantSpeechBlocked = true;
    _assistantSpokenOffset = _assistantText.length;
    _speechQueue.clear();
    _speechSerial += 1;
    _resetSpeechCancellation();
    _discardBufferedSpeech();
    unawaited(_stopPlayerSafely());
    _setSnapshot(_snapshot.copyWith(phase: AiVoiceConversationPhase.listening));
    _notifyIssue(message);
  }

  Future<void> _stopPlayerSafely() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void _fail(String message) {
    if (!_snapshot.active) return;
    _notifyIssue(message);
    _sessionSerial += 1;
    unawaited(
      _stopResources(markInactive: false).whenComplete(() {
        if (_disposed) return;
        _setSnapshot(
          _snapshot.copyWith(
            active: true,
            phase: AiVoiceConversationPhase.failed,
            inputLevel: 0,
            message: message,
          ),
        );
      }),
    );
  }

  void _resetSpeechCancellation() {
    if (!_speechCancellation.isCompleted) _speechCancellation.complete();
    _speechCancellation = Completer<void>();
  }

  void _wakeSpeechQueue() {
    final waiter = _speechQueueWaiter;
    _speechQueueWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _setSnapshot(AiVoiceConversationSnapshot next) {
    if (_disposed || identical(_snapshot, next)) return;
    _snapshot = next;
    notifyListeners();
  }

  Future<void> _stopResources({required bool markInactive}) async {
    _silenceTimer?.cancel();
    _partialRecognitionTimer?.cancel();
    _inputWatchdogTimer?.cancel();
    _silenceTimer = null;
    _partialRecognitionTimer = null;
    _inputWatchdogTimer = null;
    final cancellation = _sessionCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _sessionCancellation = null;
    _cancelPolishing();
    _speechQueue.clear();
    _wakeSpeechQueue();
    _speechSerial += 1;
    _resetSpeechCancellation();
    _discardBufferedSpeech();
    final subscription = _recordingSubscription;
    _recordingSubscription = null;
    try {
      await subscription?.cancel();
    } catch (_) {}
    try {
      await _recorder.stop();
    } catch (_) {}
    await _stopPlayerSafely();

    _recognitionModel = null;
    _synthesisModel = null;
    _recognitionConfiguration = const <String, Object?>{};
    _synthesisConfiguration = const <String, Object?>{};
    _availableModels = const <AiModelConfig>[];
    _onTextReady = null;
    _onIssue = null;
    _polishingUnavailable = false;
    _reportedIssues.clear();
    _preRoll = <int>[];
    _utterance = <int>[];
    _hasSpeech = false;
    _speechCandidateChunks = 0;
    _receivedAudioBytes = 0;
    _noiseFloor = _initialNoiseFloor;
    _maximumObservedLevel = 0;
    _inputWarningVisible = false;
    _partialRecognitionQueued = false;
    _lastPartialByteCount = 0;
    _restoredTranscriptPending = false;
    _assistantMessageId = null;
    _assistantText = '';
    _assistantSpokenOffset = 0;
    _assistantResponseStreaming = false;
    _assistantSpeechBlocked = false;
    if (markInactive && !_disposed) {
      _setSnapshot(const AiVoiceConversationSnapshot.idle());
    }
  }

  Future<void> _deleteGeneratedAudio(String path) async {
    try {
      final file = File(path);
      final parent = file.parent;
      if (await parent.exists() &&
          p.basename(parent.path).startsWith('openhand_speech_test_')) {
        await parent.delete(recursive: true);
      } else if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sessionSerial += 1;
    final cleanup = _stopResources(markInactive: false);
    unawaited(
      cleanup.whenComplete(() async {
        try {
          await _player?.dispose();
        } catch (_) {}
        if (_ownsRecorder) {
          try {
            await _recorder.dispose();
          } catch (_) {}
        }
      }),
    );
    if (_ownsPolishingService) _polishingService.dispose();
    super.dispose();
  }
}

class _StreamingPcmAudioSource {
  _StreamingPcmAudioSource._(this._server, this._audio, this._token) {
    _requests = _server.listen((request) {
      unawaited(_serve(request));
    });
  }

  static Future<_StreamingPcmAudioSource> start(
    Stream<Uint8List> audio, {
    required int sampleRate,
    required int channels,
  }) async {
    if (sampleRate <= 0 || channels <= 0) {
      throw StateError('实时音频参数无效。');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = math.Random.secure();
    final token = List<int>.generate(
      24,
      (_) => random.nextInt(256),
      growable: false,
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return _StreamingPcmAudioSource._(server, audio, token);
  }

  final HttpServer _server;
  final Stream<Uint8List> _audio;
  final String _token;
  late final StreamSubscription<HttpRequest> _requests;
  HttpResponse? _activeResponse;
  bool _claimed = false;
  bool _closed = false;
  final Completer<void> _done = Completer<void>();

  Future<void> get done => _done.future;

  Uri get uri => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
    pathSegments: <String>['speech', '$_token.pcm'],
  );

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    if (_closed || request.uri.path != '/speech/$_token.pcm') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    response.headers.contentType = ContentType.binary;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.persistentConnection = false;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    if (request.method != 'GET' || _claimed) {
      response.statusCode = HttpStatus.conflict;
      await response.close();
      return;
    }
    _claimed = true;
    _activeResponse = response;
    try {
      await response.addStream(_audio);
    } catch (error, stack) {
      if (!_closed && !_done.isCompleted) {
        _done.completeError(error, stack);
      }
    } finally {
      _activeResponse = null;
      try {
        await response.close();
      } catch (_) {}
      if (!_done.isCompleted) _done.complete();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _requests.cancel();
    } catch (_) {}
    try {
      await _server.close(force: true);
    } catch (_) {}
    try {
      await _activeResponse?.close().timeout(const Duration(seconds: 1));
    } catch (_) {}
    if (!_done.isCompleted) _done.complete();
  }
}
