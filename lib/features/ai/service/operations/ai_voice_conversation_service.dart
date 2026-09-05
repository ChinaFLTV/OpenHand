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
  static const double _speechThreshold = 0.012;
  static const Duration _partialRecognitionInterval = Duration(
    milliseconds: 950,
  );
  static const Duration _playbackTimeout = Duration(minutes: 5);
  static const int _speechChunkSoftLimit = 72;
  static const int _speechChunkHardLimit = 120;

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
  Future<void> Function(String text)? _onTextReady;

  StreamSubscription<Uint8List>? _recordingSubscription;
  Timer? _silenceTimer;
  Timer? _partialRecognitionTimer;
  Completer<void>? _sessionCancellation;
  List<int> _preRoll = <int>[];
  List<int> _utterance = <int>[];
  bool _hasSpeech = false;
  bool _partialRecognitionQueued = false;
  int _utteranceSerial = 0;
  int _sessionSerial = 0;
  int _lastPartialByteCount = 0;
  Future<void> _recognitionQueue = Future<void>.value();
  DateTime _lastLevelNotification = DateTime.fromMillisecondsSinceEpoch(0);

  mk.Player? _player;
  final List<String> _speechQueue = <String>[];
  bool _speechPumpActive = false;
  int _speechSerial = 0;
  Completer<void> _speechCancellation = Completer<void>();
  String? _assistantMessageId;
  String _assistantText = '';
  int _assistantSpokenOffset = 0;
  bool _disposed = false;

  Future<void> start({
    required OfflineSpeechSettings settings,
    required List<AiModelConfig> availableModels,
    required Future<void> Function(String text) onTextReady,
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
    _snapshot = const AiVoiceConversationSnapshot.idle().copyWith(
      active: true,
      phase: AiVoiceConversationPhase.starting,
      clearMessage: true,
    );
    notifyListeners();

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: _channelCount,
          noiseSuppress: true,
          echoCancel: true,
          autoGain: true,
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
      );
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
    if (enabled) {
      await _recorder.resume();
      _setSnapshot(
        _snapshot.copyWith(
          microphoneEnabled: true,
          phase: AiVoiceConversationPhase.listening,
          clearMessage: true,
        ),
      );
    } else {
      _silenceTimer?.cancel();
      _partialRecognitionTimer?.cancel();
      await _recorder.pause();
      if (_hasSpeech) _finalizeUtterance(force: true);
      _setSnapshot(_snapshot.copyWith(microphoneEnabled: false, inputLevel: 0));
    }
  }

  Future<void> setSpeakerMuted(bool muted) async {
    if (_snapshot.speakerMuted == muted) return;
    _speechSerial += 1;
    _resetSpeechCancellation();
    _speechQueue.clear();
    if (muted) {
      _assistantSpokenOffset = _assistantText.length;
      await _player?.stop();
    }
    _setSnapshot(_snapshot.copyWith(speakerMuted: muted));
  }

  Future<void> forceSend() async {
    if (!_snapshot.active) return;
    if (_hasSpeech) {
      _finalizeUtterance(force: true);
      return;
    }
    final current = _snapshot.currentTranscript.trim();
    if (current.isEmpty) return;
    _setSnapshot(
      _snapshot.copyWith(currentTranscript: '', previousTranscript: current),
    );
    await _deliverText(current, _sessionSerial);
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
      _speechQueue.clear();
      _speechSerial += 1;
      _resetSpeechCancellation();
      unawaited(_player?.stop());
    }
    _assistantText = text;
    if (_snapshot.speakerMuted) {
      _assistantSpokenOffset = text.length;
      return;
    }
    if (_assistantSpokenOffset > text.length) _assistantSpokenOffset = 0;
    final chunks = _extractCompletedSpeechChunks(
      text,
      start: _assistantSpokenOffset,
      flushRemainder: !streaming,
    );
    if (chunks.isEmpty) return;
    _assistantSpokenOffset = chunks.last.$2;
    _speechQueue.addAll(chunks.map((entry) => entry.$1));
    unawaited(_pumpSpeech(_sessionSerial, _speechSerial));
  }

  void resetAssistantResponse() {
    _assistantMessageId = null;
    _assistantText = '';
    _assistantSpokenOffset = 0;
    _speechQueue.clear();
    _speechSerial += 1;
    _resetSpeechCancellation();
    unawaited(_player?.stop());
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
    final level = _pcmLevel(chunk);
    final now = DateTime.now();
    if (now.difference(_lastLevelNotification) >=
        const Duration(milliseconds: 80)) {
      _lastLevelNotification = now;
      _setSnapshot(_snapshot.copyWith(inputLevel: level));
    }
    final voiced = level >= _speechThreshold;
    if (!_hasSpeech) {
      _appendPreRoll(chunk);
      if (!voiced) return;
      _hasSpeech = true;
      _utterance.addAll(_preRoll);
      _preRoll.clear();
    } else {
      _utterance.addAll(chunk);
    }
    if (voiced) {
      _silenceTimer?.cancel();
      _silenceTimer = startSafeTimer(
        _silenceTimeout,
        () => _finalizeUtterance(force: false),
      );
    }
    if (_utterance.length >= _maximumUtteranceBytes) {
      _finalizeUtterance(force: true);
      return;
    }
    if (_utterance.length >= _minimumRecognitionBytes &&
        _partialRecognitionTimer == null) {
      _partialRecognitionTimer = startSafeTimer(
        _partialRecognitionInterval,
        _queuePartialRecognition,
      );
    }
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
                text.isEmpty) {
              return;
            }
            final previous = _snapshot.currentTranscript.trim();
            _setSnapshot(
              _snapshot.copyWith(
                phase: AiVoiceConversationPhase.listening,
                previousTranscript: previous == text
                    ? _snapshot.previousTranscript
                    : previous,
                currentTranscript: text,
                clearMessage: true,
              ),
            );
          } catch (error, stack) {
            if (_snapshot.active) {
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
    final fallback = _snapshot.currentTranscript.trim();
    _utteranceSerial += 1;
    _utterance = <int>[];
    _preRoll = <int>[];
    _hasSpeech = false;
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
          try {
            final recognized = await _recognize(bytes, sessionSerial);
            if (recognized.isNotEmpty) text = recognized;
          } catch (error, stack) {
            silentLog('voice_conversation', '完成语音识别', error, stack);
            if (text.isEmpty && _isCurrentSession(sessionSerial)) {
              _setSnapshot(
                _snapshot.copyWith(
                  phase: AiVoiceConversationPhase.listening,
                  message: '识别失败：$error',
                ),
              );
            }
          }
          if (text.isNotEmpty && _isCurrentSession(sessionSerial)) {
            await _deliverText(text, sessionSerial);
          } else if (_isCurrentSession(sessionSerial)) {
            _setSnapshot(
              _snapshot.copyWith(
                phase: AiVoiceConversationPhase.listening,
                clearMessage: true,
              ),
            );
          }
        })
        .catchError((Object error, StackTrace stack) {
          if (_isCurrentSession(sessionSerial)) {
            silentLog('voice_conversation', '提交语音识别文本', error, stack);
            _setSnapshot(
              _snapshot.copyWith(
                phase: AiVoiceConversationPhase.listening,
                message: '提交识别文本失败：$error',
              ),
            );
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

  Future<void> _deliverText(String source, int sessionSerial) async {
    var text = source.trim();
    if (text.isEmpty || !_isCurrentSession(sessionSerial)) return;
    if (_polishingSettings.enabled) {
      _setSnapshot(
        _snapshot.copyWith(
          phase: AiVoiceConversationPhase.polishing,
          message: '正在润色识别文本…',
        ),
      );
      try {
        text = await _polishingService.polish(
          text: text,
          settings: _polishingSettings,
          availableModels: _availableModels,
          cancelSignal: _sessionCancellation?.future,
        );
      } catch (error, stack) {
        silentLog('voice_conversation', '润色识别文本', error, stack);
      }
    }
    if (!_isCurrentSession(sessionSerial) || text.trim().isEmpty) return;
    _setSnapshot(
      _snapshot.copyWith(
        previousTranscript: text,
        phase: AiVoiceConversationPhase.listening,
        clearMessage: true,
      ),
    );
    await _onTextReady?.call(text.trim());
  }

  Future<void> _pumpSpeech(int sessionSerial, int speechSerial) async {
    if (_speechPumpActive) return;
    _speechPumpActive = true;
    Future<String?>? prefetchedAudio;
    try {
      while ((_speechQueue.isNotEmpty || prefetchedAudio != null) &&
          _isCurrentSession(sessionSerial) &&
          speechSerial == _speechSerial &&
          !_snapshot.speakerMuted) {
        final audioPath = prefetchedAudio != null
            ? await prefetchedAudio
            : await _synthesizeSpeechChunk(
                _speechQueue.removeAt(0),
                sessionSerial,
                speechSerial,
              );
        prefetchedAudio = null;
        if (audioPath == null) continue;
        if (_speechQueue.isNotEmpty) {
          prefetchedAudio = _synthesizeSpeechChunk(
            _speechQueue.removeAt(0),
            sessionSerial,
            speechSerial,
          );
        }
        try {
          if (!_isCurrentSession(sessionSerial) ||
              speechSerial != _speechSerial ||
              _snapshot.speakerMuted) {
            continue;
          }
          _setSnapshot(
            _snapshot.copyWith(
              phase: AiVoiceConversationPhase.speaking,
              clearMessage: true,
            ),
          );
          final player = _player ??= mk.Player();
          await player.open(mk.Media(audioPath));
          await player.stream.completed
              .firstWhere((completed) => completed)
              .timeout(_playbackTimeout);
        } catch (error, stack) {
          if (_isCurrentSession(sessionSerial)) {
            silentLog('voice_conversation', '朗读流式回复', error, stack);
          }
        } finally {
          await _deleteGeneratedAudio(audioPath);
        }
      }
    } finally {
      if (prefetchedAudio != null) {
        final path = await prefetchedAudio.catchError((Object _) => null);
        if (path != null) await _deleteGeneratedAudio(path);
      }
      _speechPumpActive = false;
      if (_isCurrentSession(sessionSerial) &&
          _snapshot.phase == AiVoiceConversationPhase.speaking) {
        _setSnapshot(
          _snapshot.copyWith(phase: AiVoiceConversationPhase.listening),
        );
      }
      if (_speechQueue.isNotEmpty &&
          _snapshot.active &&
          !_snapshot.speakerMuted) {
        unawaited(_pumpSpeech(_sessionSerial, _speechSerial));
      }
    }
  }

  Future<String?> _synthesizeSpeechChunk(
    String text,
    int sessionSerial,
    int speechSerial,
  ) async {
    final model = _synthesisModel;
    if (model == null || text.isEmpty) return null;
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
        _speechQueue.clear();
        return null;
      }
      if (!_modelService.isRuntimeReady(model)) return null;
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
      return result.audioPath;
    } catch (error, stack) {
      if (_isCurrentSession(sessionSerial)) {
        silentLog('voice_conversation', '生成流式回复语音', error, stack);
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
      final englishSentenceEnd =
          character == '.' &&
          index + 1 < text.length &&
          ' \n\r\t'.contains(text[index + 1]);
      final terminalBoundary =
          '。！？!?；;\n'.contains(character) || englishSentenceEnd;
      final softBoundary =
          segmentLength >= _speechChunkSoftLimit &&
          '，,、：: '.contains(character);
      final hardBoundary =
          segmentLength >= _speechChunkHardLimit &&
          (text.codeUnitAt(index) & 0xFC00) != 0xD800;
      if (!terminalBoundary && !softBoundary && !hardBoundary) {
        continue;
      }
      final chunk = _cleanSpeechText(text.substring(segmentStart, index + 1));
      if (chunk.isNotEmpty) result.add((chunk, index + 1));
      segmentStart = index + 1;
    }
    if (flushRemainder && segmentStart < text.length) {
      final chunk = _cleanSpeechText(text.substring(segmentStart));
      if (chunk.isNotEmpty) result.add((chunk, text.length));
    }
    return result;
  }

  String _cleanSpeechText(String source) {
    return source
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'`([^`]*)`'), r'$1')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'[#>*_~]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _pcmLevel(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    var squareSum = 0.0;
    var samples = 0;
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      var sample = bytes[index] | (bytes[index + 1] << 8);
      if (sample >= 0x8000) sample -= 0x10000;
      final normalized = sample / 32768;
      squareSum += normalized * normalized;
      samples += 1;
    }
    return math.sqrt(squareSum / samples).clamp(0, 1);
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

  void _fail(String message) {
    if (!_snapshot.active) return;
    _setSnapshot(
      _snapshot.copyWith(
        phase: AiVoiceConversationPhase.failed,
        inputLevel: 0,
        message: message,
      ),
    );
    unawaited(stop());
  }

  void _resetSpeechCancellation() {
    if (!_speechCancellation.isCompleted) _speechCancellation.complete();
    _speechCancellation = Completer<void>();
  }

  void _setSnapshot(AiVoiceConversationSnapshot next) {
    if (_disposed || identical(_snapshot, next)) return;
    _snapshot = next;
    notifyListeners();
  }

  Future<void> _stopResources({required bool markInactive}) async {
    _silenceTimer?.cancel();
    _partialRecognitionTimer?.cancel();
    _silenceTimer = null;
    _partialRecognitionTimer = null;
    final cancellation = _sessionCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _sessionCancellation = null;
    _speechQueue.clear();
    _speechSerial += 1;
    _resetSpeechCancellation();
    final subscription = _recordingSubscription;
    _recordingSubscription = null;
    await subscription?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await _player?.stop();
    } catch (_) {}

    _recognitionModel = null;
    _synthesisModel = null;
    _recognitionConfiguration = const <String, Object?>{};
    _synthesisConfiguration = const <String, Object?>{};
    _availableModels = const <AiModelConfig>[];
    _onTextReady = null;
    _preRoll = <int>[];
    _utterance = <int>[];
    _hasSpeech = false;
    _partialRecognitionQueued = false;
    _lastPartialByteCount = 0;
    _assistantMessageId = null;
    _assistantText = '';
    _assistantSpokenOffset = 0;
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
        await _player?.dispose();
        if (_ownsRecorder) await _recorder.dispose();
      }),
    );
    if (_ownsPolishingService) _polishingService.dispose();
    super.dispose();
  }
}
