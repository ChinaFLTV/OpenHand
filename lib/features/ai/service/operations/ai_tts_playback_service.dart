import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../app/support/openhand_paths.dart';
import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/net/http_error_message.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_base64.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/bounded_json_conversion.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/lifecycle_cache.dart';
import '../../../../shared/util/stable_hash.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../../../shared/util/xml_escape.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_creation_mode.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_tts_provider_catalog.dart';
import '../../model/ai_tts_settings.dart';
import '../media/ai_image_generation_service.dart';
import '../runtime/ai_transport_client.dart';
import '../usage/ai_usage_tracker.dart';

typedef AiTtsTransportFactory = AiTransportClient Function();

class AiTtsPlaybackSnapshot {
  const AiTtsPlaybackSnapshot({
    this.playing = false,
    this.messageId,
    this.provider,
    this.error,
    this.failureId,
  });

  final bool playing;
  final String? messageId;
  final AiTtsProvider? provider;
  final String? error;
  final int? failureId;
}

class AiTtsPlaybackService {
  AiTtsPlaybackService({
    AiImageGenerationService? mediaGenerationService,
    AiTtsTransportFactory? transportFactory,
  }) : _mediaGenerationService =
           mediaGenerationService ?? AiImageGenerationService(),
       _ownsMediaGenerationService = mediaGenerationService == null,
       _transportFactory = transportFactory ?? (() => AiTransportClient());

  static const String settingsTestMessageId = '__settings_tts_test__';
  static const String settingsTestText = '这是一段文本转语音测试。';
  static const int _doubaoTtsSuccessCode = 20000000;
  static const String _defaultAiTtsAudioFormat = 'mp3';
  static const int _defaultAiTtsSampleRate = 24000;
  static const int _defaultAiTtsBitRate = 128000;
  static const int _audioCacheMaxEntries = 48;
  static const int _audioCacheMaxBytes = 64 * kBytesPerMiB;
  static const int _maxAudioResponseBytes = _audioCacheMaxBytes;
  static const int _maxAudioJsonResponseBytes = 96 * kBytesPerMiB;
  static const int _maxControlResponseBytes = kBytesPerMiB;
  static const int _maxDoubaoFrameChars = 16 * kBytesPerMiB;
  static const int _maxWebSocketEventChars = 16 * kBytesPerMiB;
  static const BoundedJsonConversionConfig _jsonConversionConfig =
      BoundedJsonConversionConfig(
        maxDepth: 32,
        maxContainerItems: 65536,
        maxTotalNodes: 262144,
      );
  static const int _mimoMaxVoiceSampleBase64Bytes = 10 * kBytesPerMiB;
  static const int _mimoMaxVoiceSampleRawBytes =
      (_mimoMaxVoiceSampleBase64Bytes ~/ 4) * 3;
  static const Duration _fileReadIdleTimeout = Duration(seconds: 15);
  static const Duration _networkIdleTimeout = Duration(seconds: 30);
  static const Duration _resourceCloseTimeout = Duration(seconds: 2);
  static const Duration _playbackFileIoTimeout = Duration(seconds: 30);
  static const Duration _stalePlaybackCleanupTimeout = Duration(seconds: 2);
  static const Duration _stalePlaybackFileAge = Duration(days: 1);
  static const int _stalePlaybackScanLimit = 256;
  static const int _stalePlaybackDeleteLimit = 64;
  static const Duration _speechProcessPipeDrainTimeout = Duration(
    milliseconds: 300,
  );
  static const Duration _speechProcessStartTimeout = Duration(seconds: 10);
  static const Duration _speechProcessTerminateGrace = Duration(
    milliseconds: 500,
  );
  static const Duration _audioDurationProbeTimeout = Duration(seconds: 2);
  static const Duration _audiblePlaybackMinTimeout = Duration(seconds: 45);
  static const Duration _audiblePlaybackGrace = Duration(seconds: 12);
  static const Duration _audiblePlaybackMaxTimeout = Duration(minutes: 45);
  static const double _audiblePlaybackGraceRatio = 0.15;
  static const int _defaultSpeechCharsPerMinute = 300;
  static const int _minSpeechCharsPerMinute = 120;
  static const int _maxSpeechCharsPerMinute = 900;
  static const int _conservativeCompressedAudioBitRate = 48000;
  static const int _minCompressedAudioBitRate = 24000;
  static const int _maxCompressedAudioBitRate = 320000;
  static const int _pcm16BytesPerSample = 2;
  static const int _minimumWavBytes = 44;
  static final RegExp _markdownMediaLinkPattern = RegExp(r'\]\(([^)]+)\)');
  static final RegExp _markdownLinkTitlePattern = RegExp(r'\s+"');
  static final RegExp _afinfoDurationPattern = RegExp(
    r'(?:estimated\s+)?duration:\s*([0-9]+(?:\.[0-9]+)?)',
    caseSensitive: false,
  );
  static final RegExp _audioBitRatePattern = RegExp(
    r'(\d+)\s*k(?:bitrate|bps|b)?',
    caseSensitive: false,
  );
  static final RegExp _macOsVoiceColumnSeparatorPattern = RegExp(r'\s{2,}');
  static final RegExp _markdownCodeBlockPattern = RegExp(r'```[\s\S]*?```');
  static final LifecycleLruCache<_AiTtsAudioPayload> _audioCache =
      LifecycleLruCache<_AiTtsAudioPayload>(
        maxEntries: _audioCacheMaxEntries,
        maxCost: _audioCacheMaxBytes,
        costOf: (audio) => audio.byteLength,
      );

  final AiImageGenerationService _mediaGenerationService;
  final bool _ownsMediaGenerationService;
  final AiTtsTransportFactory _transportFactory;
  final ValueNotifier<AiTtsPlaybackSnapshot> state =
      ValueNotifier<AiTtsPlaybackSnapshot>(const AiTtsPlaybackSnapshot());
  int _generation = 0;
  int _failureSerial = 0;
  int _tempFileSerial = 0;
  _AiTtsOperation? _activeOperation;
  Future<void>? _stalePlaybackCleanupFuture;
  late final OpenHandRetryableAsyncCache<Set<String>> _macOsVoiceNamesCache =
      OpenHandRetryableAsyncCache<Set<String>>(_loadMacOsVoiceNames);
  Future<void>? _disposeFuture;
  bool _disposed = false;

  bool isPlayingMessage(String messageId) {
    if (_disposed) return false;
    final snapshot = state.value;
    return snapshot.playing && snapshot.messageId == messageId;
  }

  Future<void> toggleMessage({
    required String messageId,
    required String text,
    required AiTtsSettings settings,
    List<AiModelConfig> availableModels = const <AiModelConfig>[],
    AiModelConfig? fallbackModel,
  }) async {
    _throwIfDisposed();
    if (isPlayingMessage(messageId)) {
      await stop();
      return;
    }
    await speak(
      messageId: messageId,
      text: text,
      settings: settings,
      availableModels: availableModels,
      fallbackModel: fallbackModel,
    );
  }

  Future<void> speak({
    required String messageId,
    required String text,
    required AiTtsSettings settings,
    List<AiModelConfig> availableModels = const <AiModelConfig>[],
    AiModelConfig? fallbackModel,
  }) async {
    final reservation = _reservePlayback();
    if (!await _prepareReservedPlayback(reservation)) return;
    final normalized = settings.normalized();
    if (!normalized.enabled) return;
    final content = _normalizeText(text, normalized.maxTextCharacters);
    if (content.isEmpty) return;
    final generation = reservation.generation;
    final synthesisTimeout = Duration(seconds: normalized.timeoutSeconds);
    final synthesisDeadline = MonotonicDeadline(
      synthesisTimeout,
      timeoutMessage: 'TTS 合成超过总时限。',
    );
    Object? lastError;
    StackTrace? lastStack;
    var attemptedProvider = false;
    for (final provider in normalized.providerPriority) {
      if (generation != _generation) return;
      final providerSettings = normalized.provider(provider);
      if (!providerSettings.enabled) continue;
      attemptedProvider = true;
      final remaining = synthesisDeadline.remainingOrNull();
      if (remaining == null) {
        lastError ??= synthesisDeadline.timeoutException();
        break;
      }
      final operation = _AiTtsOperation(
        timeout: remaining,
        transport: _transportFactory(),
      );
      _activeOperation = operation;
      bool isCurrent() {
        return _isCurrentGeneration(generation) &&
            identical(_activeOperation, operation) &&
            !operation.isCancelled;
      }

      if (!_publishState(
        generation,
        AiTtsPlaybackSnapshot(
          playing: true,
          messageId: messageId,
          provider: provider,
        ),
      )) {
        await _releaseOperation(operation);
        return;
      }
      try {
        await _speakWithProvider(
          providerSettings,
          content,
          operation: operation,
          availableModels: availableModels,
          fallbackModel: fallbackModel,
          isCurrent: isCurrent,
        );
        if (isCurrent()) await stop();
        return;
      } catch (error, stack) {
        await _releaseOperation(operation);
        if (error is _AiTtsPlaybackCancelled) return;
        if (!_isCurrentGeneration(generation)) return;
        lastError = error;
        lastStack = stack;
        if (!isAiTtsConfigurationError(error)) {
          silentLog(
            'ai_tts_playback_service',
            '调用供应商 ${provider.storageKey}',
            error,
            stack,
          );
        }
      }
    }
    if (_isCurrentGeneration(generation)) {
      final error =
          lastError ??
          StateError(
            attemptedProvider ? '所有已配置的 TTS 供应商均调用失败。' : '没有可用的已启用 TTS 供应商。',
          );
      _publishState(
        generation,
        AiTtsPlaybackSnapshot(
          messageId: messageId,
          error: _playbackFailureMessage(error),
          failureId: ++_failureSerial,
        ),
      );
      Error.throwWithStackTrace(error, lastStack ?? StackTrace.current);
    }
  }

  Future<bool> testProvider({
    required AiTtsSettings settings,
    required AiTtsProvider provider,
    String text = settingsTestText,
    List<AiModelConfig> availableModels = const <AiModelConfig>[],
    AiModelConfig? fallbackModel,
  }) async {
    final reservation = _reservePlayback();
    if (!await _prepareReservedPlayback(reservation)) return false;
    final normalized = settings.normalized();
    final content = _normalizeText(text, normalized.maxTextCharacters);
    if (content.isEmpty) {
      throw StateError('TTS 测试文本不能为空。');
    }
    final providerSettings = normalized.provider(provider);
    final generation = reservation.generation;
    final operation = _AiTtsOperation(
      timeout: Duration(seconds: normalized.timeoutSeconds),
      transport: _transportFactory(),
    );
    _activeOperation = operation;
    bool isCurrent() {
      return _isCurrentGeneration(generation) &&
          identical(_activeOperation, operation) &&
          !operation.isCancelled;
    }

    if (!_publishState(
      generation,
      AiTtsPlaybackSnapshot(
        playing: true,
        messageId: settingsTestMessageId,
        provider: provider,
      ),
    )) {
      await _releaseOperation(operation);
      return false;
    }
    var completed = false;
    try {
      await _speakWithProvider(
        providerSettings,
        content,
        operation: operation,
        availableModels: availableModels,
        fallbackModel: fallbackModel,
        isCurrent: isCurrent,
      );
      completed = isCurrent();
    } on _AiTtsPlaybackCancelled {
      return false;
    } catch (_) {
      if (!isCurrent()) return false;
      rethrow;
    } finally {
      await _releaseOperation(operation);
      _publishState(generation, const AiTtsPlaybackSnapshot());
    }
    return completed && _isCurrentGeneration(generation);
  }

  Future<void> stop() {
    if (_disposed) return _disposeFuture ?? Future<void>.value();
    final generation = ++_generation;
    final operation = _activeOperation;
    _publishState(generation, const AiTtsPlaybackSnapshot());
    return operation == null
        ? Future<void>.value()
        : _releaseOperation(operation);
  }

  Future<void> _releaseOperation(_AiTtsOperation operation) async {
    try {
      await operation.close();
    } finally {
      if (identical(_activeOperation, operation)) {
        _activeOperation = null;
      }
    }
  }

  ({int generation, _AiTtsOperation? previous}) _reservePlayback() {
    _throwIfDisposed();
    final previous = _activeOperation;
    final generation = ++_generation;
    _publishState(generation, const AiTtsPlaybackSnapshot());
    return (generation: generation, previous: previous);
  }

  Future<bool> _prepareReservedPlayback(
    ({int generation, _AiTtsOperation? previous}) reservation,
  ) async {
    final previous = reservation.previous;
    if (previous != null) {
      await _releaseOperation(previous);
    }
    return _isCurrentGeneration(reservation.generation);
  }

  bool _isCurrentGeneration(int generation) {
    return !_disposed && generation == _generation;
  }

  bool _publishState(int generation, AiTtsPlaybackSnapshot snapshot) {
    if (!_isCurrentGeneration(generation)) return false;
    state.value = snapshot;
    return _isCurrentGeneration(generation);
  }

  void _throwIfDisposed() {
    if (_disposed) throw StateError('TTS 播放服务已关闭。');
  }

  Future<void> dispose() {
    final active = _disposeFuture;
    if (active != null) return active;
    final completer = Completer<void>();
    _disposeFuture = completer.future;
    _disposed = true;
    _generation += 1;
    state.value = const AiTtsPlaybackSnapshot();
    final operation = _activeOperation;
    unawaited(
      _finishDispose(operation).then<void>(
        (_) => completer.complete(),
        onError: (Object error, StackTrace stack) {
          silentLog('ai_tts_playback_service', '关闭播放服务', error, stack);
          completer.complete();
        },
      ),
    );
    return completer.future;
  }

  Future<void> _finishDispose(_AiTtsOperation? operation) async {
    if (operation != null) {
      await runAsyncCleanupBounded(
        () => _releaseOperation(operation),
        timeout: const Duration(seconds: 8),
        onError: (error, stack) =>
            silentLog('ai_tts_playback_service', '关闭当前播放任务', error, stack),
      );
    }
    if (_ownsMediaGenerationService) {
      await runAsyncCleanupBounded(
        _mediaGenerationService.dispose,
        onError: (error, stack) =>
            silentLog('ai_tts_playback_service', '关闭媒体生成服务', error, stack),
      );
    }
    await runAsyncCleanupBounded(
      state.dispose,
      onError: (error, stack) =>
          silentLog('ai_tts_playback_service', '关闭播放状态', error, stack),
    );
  }

  static bool supportsAudioGenerationModel(
    AiModelConfig config,
    String modelId,
  ) {
    final normalizedModelId = modelId.trim();
    if (normalizedModelId.isEmpty) return false;
    if (config.protocolType == AiProtocolType.minimax &&
        !AiTtsProviderCatalogs.usesMiniMaxSpeech(
          protocol: config.protocolType,
          modelId: normalizedModelId,
        )) {
      return false;
    }
    final candidate = config.copyWith(modelId: normalizedModelId);
    final profile = candidate.profileFor(normalizedModelId);
    final modalities = profile.supportedModalities;
    final multimodal =
        profile.isMultimodal == true ||
        modalities.length > 1 ||
        (modalities.contains(AiModelModality.text) &&
            modalities.contains(AiModelModality.audio));
    return multimodal &&
        profile.capabilities.contains(AiModelCapability.audioGeneration) &&
        AiImageGenerationService.supportsAudioGenerationForModel(candidate);
  }

  Future<void> _speakWithProvider(
    AiTtsProviderSettings provider,
    String text, {
    required _AiTtsOperation operation,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
    if (!_isCacheableTtsProvider(provider.provider)) {
      await _speakWithSystem(
        provider,
        text,
        timeout: operation.timeout,
        operation: operation,
        isCurrent: isCurrent,
      );
      return;
    }
    final resolvedAiModel = provider.provider == AiTtsProvider.ai
        ? _resolveAiModel(
            settings: provider,
            availableModels: availableModels,
            fallbackModel: fallbackModel,
          )
        : null;
    final cacheKey = await _ttsAudioCacheKey(
      provider: provider,
      text: text,
      timeout: operation.remainingSynthesisTime(),
      availableModels: availableModels,
      fallbackModel: fallbackModel,
    );
    var audio = _audioCache.get(cacheKey);
    if (audio != null &&
        provider.provider == AiTtsProvider.mimo &&
        _mimoUsesWavOutput(provider)) {
      try {
        _validateMimoWavAudio(audio.bytes);
      } catch (_) {
        audio = null;
      }
    }
    if (audio == null) {
      audio = await _synthesizeWithProvider(
        provider,
        text,
        operation: operation,
        availableModels: availableModels,
        fallbackModel: fallbackModel,
      );
      if (provider.provider == AiTtsProvider.mimo &&
          _mimoUsesWavOutput(provider)) {
        _validateMimoWavAudio(audio.bytes);
      }
      _audioCache.put(cacheKey, audio);
    }
    operation.throwIfCancelled();
    if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
    await _playAudioBytes(
      audio.bytes,
      extension: audio.extension,
      volume: _playbackVolume(provider, aiModel: resolvedAiModel),
      provider: provider,
      requestTimeout: operation.timeout,
      operation: operation,
      isCurrent: isCurrent,
    );
  }

  Future<_AiTtsAudioPayload> _synthesizeWithProvider(
    AiTtsProviderSettings provider,
    String text, {
    required _AiTtsOperation operation,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
  }) {
    switch (provider.provider) {
      case AiTtsProvider.ai:
        return _synthesizeWithAiModel(
          provider,
          text,
          operation: operation,
          availableModels: availableModels,
          fallbackModel: fallbackModel,
        );
      case AiTtsProvider.system:
      case AiTtsProvider.apple:
        throw StateError('系统 TTS 不支持缓存。');
      case AiTtsProvider.xfyun:
        return _synthesizeWithXfyun(provider, text, operation: operation);
      case AiTtsProvider.baidu:
        return _synthesizeWithBaidu(provider, text, operation: operation);
      case AiTtsProvider.doubao:
        return _synthesizeWithDoubao(provider, text, operation: operation);
      case AiTtsProvider.mimo:
        return _synthesizeWithMimo(provider, text, operation: operation);
      case AiTtsProvider.youdao:
        return _synthesizeWithYoudao(provider, text, operation: operation);
      case AiTtsProvider.bing:
        return _synthesizeWithBing(provider, text, operation: operation);
      case AiTtsProvider.google:
        return _synthesizeWithGoogle(provider, text, operation: operation);
    }
  }

  Future<_AiTtsAudioPayload> _synthesizeWithAiModel(
    AiTtsProviderSettings settings,
    String text, {
    required _AiTtsOperation operation,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
  }) async {
    final model = _resolveAiModel(
      settings: settings,
      availableModels: availableModels,
      fallbackModel: fallbackModel,
    );
    if (model == null) {
      throw StateError('AI TTS 模型不能为空。');
    }
    if (!supportsAudioGenerationModel(model, model.modelId)) {
      throw StateError('AI TTS 模型不支持音频生成。');
    }
    final requestedFormat = _extraString(
      settings,
      'format',
      fallback: _defaultAiTtsAudioFormat,
    );
    final stepFunSpeech = AiTtsProviderCatalogs.usesStepFunSpeech(
      protocol: model.protocolType,
      modelId: model.modelId,
    );
    final outputFormat = stepFunSpeech
        ? AiTtsProviderCatalogs.normalizeStepFunResponseFormat(requestedFormat)
        : requestedFormat;
    final voice = AiTtsProviderCatalogs.normalizeVoiceForAiModel(
      voice: settings.voice,
      protocol: model.protocolType,
      modelId: model.modelId,
    );
    final result = await AiUsageTraceContext.runDerived(
      source: AiUsageSource.textToSpeech,
      operation: 'speech_synthesis',
      body: () async {
        final startedAt = DateTime.now().toUtc();
        final requestTimeout = operation.remainingSynthesisTime();
        try {
          final generated = await operation.runTrackedActivity(
            () => _mediaGenerationService.generateAudio(
              model: model,
              prompt: text,
              options: AiCreationOptions(
                voice: nullIfBlank(voice),
                speed: settings.speed,
                volume: settings.volume,
                pitch: settings.pitch,
                outputFormat: outputFormat,
                sampleRate: _extraInt(
                  settings,
                  'sample_rate',
                  fallback: _defaultAiTtsSampleRate,
                ),
                bitrate: _extraInt(
                  settings,
                  'bit_rate',
                  fallback: _defaultAiTtsBitRate,
                ),
                languageBoost: _extraString(settings, 'language_boost'),
                emotion: _extraString(settings, 'emotion'),
                textNormalization: _extraBool(settings, 'text_normalization'),
                latexRead: _extraBool(settings, 'latex_read'),
                channel: _extraInt(settings, 'channel', fallback: 1),
                forceCbr: _extraBool(settings, 'force_cbr'),
                subtitleEnable: _extraBool(settings, 'subtitle_enable'),
                subtitleType: _extraString(
                  settings,
                  'subtitle_type',
                  fallback: 'sentence',
                ),
                pronunciationTone: stringListFromListValue(
                  settings.extra['pronunciation_tone'],
                ),
                timbreWeights: stringKeyedMapListFromValue(
                  settings.extra['timbre_weights'],
                ),
                voiceModify: settings.extra['voice_modify'] is Map
                    ? stringKeyedMapFromValue(settings.extra['voice_modify'])
                    : const <String, Object?>{},
              ),
              timeout: requestTimeout,
              cancelSignal: operation.cancelSignal,
            ),
          );
          AiUsageTracker.instance.recordSuccess(
            model: model,
            apiFamily: AiApiFamily.audioSpeech.storageValue,
            startedAt: startedAt,
            endedAt: DateTime.now().toUtc(),
            inputCharacters: text.length,
            outputCharacters: 0,
            usage: generated.usage,
          );
          return generated;
        } on AiMediaGenerationCancelledException catch (error) {
          AiUsageTracker.instance.recordFailure(
            model: model,
            apiFamily: AiApiFamily.audioSpeech.storageValue,
            startedAt: startedAt,
            endedAt: DateTime.now().toUtc(),
            error: error,
            cancelled: true,
          );
          operation.throwIfCancelled();
          rethrow;
        } catch (error) {
          AiUsageTracker.instance.recordFailure(
            model: model,
            apiFamily: AiApiFamily.audioSpeech.storageValue,
            startedAt: startedAt,
            endedAt: DateTime.now().toUtc(),
            error: error,
            timeout: requestTimeout,
          );
          rethrow;
        }
      },
    );
    operation.throwIfCancelled();
    final audioReference = _firstMediaReference(result.markdown);
    if (audioReference.isEmpty) {
      throw StateError('AI TTS 未返回可播放音频。');
    }
    return _audioPayloadFromReference(
      audioReference,
      outputFormat: outputFormat,
      operation: operation,
    );
  }

  AiModelConfig? _resolveAiModel({
    required AiTtsProviderSettings settings,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
  }) {
    final configId = settings.modelConfigId.trim();
    final modelId = settings.modelId.trim();
    if (configId.isNotEmpty && modelId.isNotEmpty) {
      for (final config in availableModels) {
        if (config.id == configId &&
            config.allModelIds.contains(modelId) &&
            supportsAudioGenerationModel(config, modelId)) {
          return config.copyWith(modelId: modelId);
        }
      }
    }
    if (fallbackModel != null &&
        supportsAudioGenerationModel(fallbackModel, fallbackModel.modelId)) {
      return fallbackModel;
    }
    return null;
  }

  Future<String> _ttsAudioCacheKey({
    required AiTtsProviderSettings provider,
    required String text,
    required Duration timeout,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
  }) async {
    final resolvedModel = provider.provider == AiTtsProvider.ai
        ? _resolveAiModel(
            settings: provider,
            availableModels: availableModels,
            fallbackModel: fallbackModel,
          )
        : null;
    return 'ai_tts_audio:${provider.provider.storageKey}:${stableJsonSha256(<String, Object?>{
      'version': 1,
      'text_sha256': stableJsonSha256(text),
      'provider': provider.provider.storageKey,
      'provider_settings': provider.toJson(),
      'effective_endpoint': _endpointOrDefault(provider),
      if (provider.provider == AiTtsProvider.ai) ...<String, Object?>{'model': resolvedModel?.toJson(), 'audio_request': resolvedModel == null ? null : _aiTtsCacheDetails(provider, resolvedModel)},
      if (provider.provider == AiTtsProvider.mimo) 'voice_sample': await _mimoVoiceSampleCacheToken(provider, timeout: timeout),
    })}';
  }

  Map<String, Object?> _aiTtsCacheDetails(
    AiTtsProviderSettings settings,
    AiModelConfig model,
  ) {
    final requestedFormat = _extraString(
      settings,
      'format',
      fallback: _defaultAiTtsAudioFormat,
    );
    final stepFunSpeech = AiTtsProviderCatalogs.usesStepFunSpeech(
      protocol: model.protocolType,
      modelId: model.modelId,
    );
    final outputFormat = stepFunSpeech
        ? AiTtsProviderCatalogs.normalizeStepFunResponseFormat(requestedFormat)
        : requestedFormat;
    return <String, Object?>{
      'protocol': model.protocolType.storageValue,
      'model_id': model.modelId,
      'voice': AiTtsProviderCatalogs.normalizeVoiceForAiModel(
        voice: settings.voice,
        protocol: model.protocolType,
        modelId: model.modelId,
      ),
      'speed': settings.speed,
      'volume': settings.volume,
      'pitch': settings.pitch,
      'output_format': outputFormat,
      'sample_rate': _extraInt(
        settings,
        'sample_rate',
        fallback: _defaultAiTtsSampleRate,
      ),
      'bit_rate': _extraInt(
        settings,
        'bit_rate',
        fallback: _defaultAiTtsBitRate,
      ),
    };
  }

  Future<Map<String, Object?>?> _mimoVoiceSampleCacheToken(
    AiTtsProviderSettings settings, {
    required Duration timeout,
  }) async {
    final model = _extraString(settings, 'model', fallback: 'mimo-v2.5-tts');
    if (!_mimoUsesVoiceClone(model)) return null;
    final path = _extraString(settings, 'voice_sample_path');
    if (path.isEmpty) return const <String, Object?>{'path': ''};
    try {
      final stat = await File(path).stat().timeout(timeout);
      return <String, Object?>{
        'path': path,
        'type': stat.type.toString(),
        'size': stat.size,
        'modified': stat.modified.toUtc().toIso8601String(),
        'changed': stat.changed.toUtc().toIso8601String(),
      };
    } catch (_) {
      return <String, Object?>{'path': path, 'stat_error': true};
    }
  }

  String _endpointOrDefault(AiTtsProviderSettings settings) {
    return nullIfBlank(settings.endpoint) ??
        AiTtsProviderSettings.defaults(settings.provider).endpoint;
  }

  static bool _isCacheableTtsProvider(AiTtsProvider provider) {
    return provider != AiTtsProvider.system && provider != AiTtsProvider.apple;
  }

  static double _playbackVolume(
    AiTtsProviderSettings settings, {
    AiModelConfig? aiModel,
  }) {
    switch (settings.provider) {
      case AiTtsProvider.ai:
        return _aiPlaybackVolume(settings, aiModel: aiModel);
      case AiTtsProvider.mimo:
      case AiTtsProvider.youdao:
      case AiTtsProvider.system:
      case AiTtsProvider.apple:
        return _unitPlaybackVolume(settings.volume);
      case AiTtsProvider.xfyun:
      case AiTtsProvider.baidu:
      case AiTtsProvider.bing:
      case AiTtsProvider.google:
      case AiTtsProvider.doubao:
        return 1.0;
    }
  }

  static double _aiPlaybackVolume(
    AiTtsProviderSettings settings, {
    AiModelConfig? aiModel,
  }) {
    final modelId = (aiModel?.modelId ?? settings.modelId).trim();
    final protocol = aiModel?.protocolType;
    final fallbackProtocol = protocol ?? AiProtocolType.openai;
    final synthesisAppliesVolume =
        AiTtsProviderCatalogs.usesStepFunSpeech(
          protocol: fallbackProtocol,
          modelId: modelId,
        ) ||
        AiTtsProviderCatalogs.usesMiniMaxSpeech(
          protocol: fallbackProtocol,
          modelId: modelId,
        );
    return synthesisAppliesVolume ? 1.0 : _unitPlaybackVolume(settings.volume);
  }

  static double _unitPlaybackVolume(double volume) {
    if (!volume.isFinite) return 1.0;
    return clampUnitInterval(volume);
  }

  Future<_AiTtsAudioPayload> _synthesizeWithMimo(
    AiTtsProviderSettings settings,
    String text, {
    required _AiTtsOperation operation,
  }) async {
    if (settings.apiKey.isEmpty) {
      throw StateError('Mimo TTS API 密钥不能为空。');
    }
    final endpoint = _endpointOrDefault(settings);
    final uri = Uri.parse(endpoint);
    final model = _extraString(settings, 'model', fallback: 'mimo-v2.5-tts');
    final requestedFormat = lowercaseStringFromValue(
      settings.extra['format'],
      fallback: aiMimoDefaultAudioFormat,
    );
    final audioFormat = requestedFormat == 'mp3'
        ? 'mp3'
        : aiMimoDefaultAudioFormat;
    final audio = <String, Object?>{
      'format': audioFormat,
      if (_mimoUsesPresetVoice(model)) 'voice': settings.voice.trim(),
      if (_mimoUsesVoiceClone(model))
        'voice': await _mimoVoiceSampleDataUrl(settings, operation: operation),
      if (!_mimoUsesPresetVoice(model) &&
          _extraBool(settings, 'optimize_text_preview'))
        'optimize_text_preview': true,
    };
    if (_mimoUsesPresetVoice(model) &&
        (audio['voice'] as String?)?.isEmpty != false) {
      throw StateError('Mimo TTS 音色不能为空。');
    }
    final response = await operation.transport.sendJson(
      uri: uri,
      method: 'POST',
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: kApplicationJsonUtf8ContentType,
        HttpHeaders.acceptHeader: kApplicationJsonMimeType,
        'api-key': settings.apiKey,
      },
      body: <String, Object?>{
        'model': model,
        'stream': false,
        'messages': <Object?>[
          <String, Object?>{
            'role': 'user',
            'content': _mimoStylePrompt(settings),
          },
          <String, Object?>{'role': 'assistant', 'content': text},
        ],
        'audio': audio,
      },
      timeout: operation.remainingSynthesisTime(),
      maxResponseBytes: _maxAudioJsonResponseBytes,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw HttpException(
        'Mimo TTS 请求失败（HTTP ${response.statusCode}）：${_shortBody(response)}',
        uri: uri,
      );
    }
    operation.throwIfCancelled();
    final audioBytes = await compute(_decodeMimoAudioPayload, <String, Object?>{
      'body': response.body,
      'format': audioFormat,
      'sample_rate': _extraInt(settings, 'sample_rate', fallback: 24000),
      'max_audio_bytes': _maxAudioResponseBytes,
    });
    operation.throwIfCancelled();
    return _AiTtsAudioPayload(
      audioBytes,
      extension: _mimoAudioExtension(audioFormat),
    );
  }

  Future<String> _mimoVoiceSampleDataUrl(
    AiTtsProviderSettings settings, {
    required _AiTtsOperation operation,
  }) async {
    final path = _extraString(settings, 'voice_sample_path');
    if (path.isEmpty) {
      throw StateError('Mimo TTS 音色样本路径不能为空。');
    }
    final mimeType = _mimoVoiceSampleMimeType(path);
    if (mimeType == null) {
      throw StateError('Mimo TTS 音色样本格式必须为 MP3 或 WAV。');
    }
    final file = File(path);
    final remaining = operation.remainingSynthesisTime();
    final bytes = await operation.runTrackedActivity(
      () => readBoundedFileBytes(
        file,
        maxBytes: _mimoMaxVoiceSampleRawBytes,
        idleTimeout: remaining < _fileReadIdleTimeout
            ? remaining
            : _fileReadIdleTimeout,
        totalTimeout: remaining,
        handleOwner: operation,
      ),
    );
    operation.throwIfCancelled();
    if (bytes.isEmpty) {
      throw StateError('Mimo TTS 音色样本文件不能为空。');
    }
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  Future<_AiTtsAudioPayload> _synthesizeWithDoubao(
    AiTtsProviderSettings settings,
    String text, {
    required _AiTtsOperation operation,
  }) async {
    if (settings.apiKey.isEmpty) {
      throw StateError('豆包 TTS API 密钥不能为空。');
    }
    final speaker = settings.voice.trim();
    if (speaker.isEmpty) {
      throw StateError('豆包 TTS 发音人不能为空。');
    }
    final endpoint = _endpointOrDefault(settings);
    final uri = Uri.parse(endpoint);
    final resourceId = _extraString(
      settings,
      'resource_id',
      fallback: 'seed-tts-2.0',
    );
    final configuredRequestId = _extraString(settings, 'request_id');
    final requestId = configuredRequestId.isEmpty
        ? const Uuid().v4()
        : configuredRequestId;
    final audioFormat = _extraString(settings, 'format', fallback: 'mp3');
    final requestModel = _extraString(settings, 'model');
    final explicitLanguage = optionalLowercaseStringFromValue(
      settings.language,
    );
    final requestBody = <String, Object?>{
      'req_params': <String, Object?>{
        'text': text,
        'speaker': speaker,
        if (requestModel.isNotEmpty) 'model': requestModel,
        'audio_params': <String, Object?>{
          'format': audioFormat,
          'sample_rate': _extraInt(settings, 'sample_rate', fallback: 24000),
          'bit_rate': _extraInt(settings, 'bit_rate', fallback: 128000),
          'speech_rate': settings.speed.round().clamp(-50, 100),
          'loudness_rate': settings.volume.round().clamp(-50, 100),
        },
        'additions': jsonEncode(<String, Object?>{
          'disable_markdown_filter': _extraBool(
            settings,
            'disable_markdown_filter',
          ),
          'disable_emoji_filter': _extraBool(settings, 'disable_emoji_filter'),
          if (explicitLanguage != null) 'explicit_language': explicitLanguage,
        }),
        'post_process': <String, Object?>{
          'pitch': settings.pitch.round().clamp(-12, 12),
        },
      },
    };
    return operation.transport.consumeJsonStream<_AiTtsAudioPayload>(
      uri: uri,
      method: 'POST',
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: kApplicationJsonUtf8ContentType,
        HttpHeaders.acceptHeader: kApplicationJsonMimeType,
        'X-Api-Key': settings.apiKey,
        'X-Api-Resource-Id': resourceId,
        'X-Api-Request-Id': requestId,
        HttpHeaders.connectionHeader: kConnectionKeepAlive,
      },
      body: requestBody,
      timeout: operation.remainingSynthesisTime(),
      maxResponseBytes: _maxAudioJsonResponseBytes,
      consume: (_, stream) async {
        final audioBytes = BytesBuilder(copy: false);
        final parser = _DoubaoJsonObjectParser(
          maxObjectChars: _maxDoubaoFrameChars,
          onObject: (payload) {
            _handleDoubaoPayload(
              payload,
              onAudio: (audio) => _appendBoundedBase64Audio(
                audioBytes,
                audio,
                maxBytes: _maxAudioResponseBytes,
              ),
            );
          },
        );
        await for (final chunk in stream.transform(utf8.decoder)) {
          operation.throwIfCancelled();
          parser.add(chunk);
        }
        parser.finish();
        operation.throwIfCancelled();
        return _AiTtsAudioPayload(
          audioBytes.takeBytes(),
          extension: _audioExtension(audioFormat),
        );
      },
    );
  }

  Future<void> _speakWithSystem(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
    required _AiTtsOperation operation,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
    final playbackTimeout = _speechProcessTimeoutForText(
      text,
      settings,
      requestTimeout: timeout,
    );
    if (Platform.isMacOS) {
      final voice = await _resolveMacOsVoice(
        settings.voice,
      ).timeout(const Duration(seconds: 2), onTimeout: () => '');
      if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
      if (voice.isNotEmpty) {
        await _runSpeechProcess(
          'say',
          <String>['-v', voice, '-r', '${_systemRate(settings.speed)}', text],
          timeout: playbackTimeout,
          operation: operation,
        );
        return;
      }
      await _runSpeechProcess(
        'osascript',
        <String>['-e', _macOsSpeechScript(text, settings)],
        timeout: playbackTimeout,
        operation: operation,
      );
      return;
    }
    if (Platform.isWindows) {
      if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
      final script = _windowsSpeechScript(text, settings);
      await _runSpeechProcess(
        'powershell',
        <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
        timeout: playbackTimeout,
        operation: operation,
      );
      return;
    }
    if (Platform.isLinux) {
      if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
      await _runSpeechProcess(
        'spd-say',
        <String>['-r', '${_linuxRate(settings.speed)}', text],
        timeout: playbackTimeout,
        operation: operation,
      );
      return;
    }
    throw UnsupportedError('当前平台不支持系统 TTS。');
  }

  Future<_AiTtsAudioPayload> _synthesizeWithXfyun(
    AiTtsProviderSettings settings,
    String text, {
    required _AiTtsOperation operation,
  }) async {
    if (settings.appId.isEmpty ||
        settings.apiKey.isEmpty ||
        settings.apiSecret.isEmpty) {
      throw StateError('讯飞 TTS 凭据不完整。');
    }
    final endpoint = _endpointOrDefault(settings);
    final uri = _xfyunAuthorizedUri(Uri.parse(endpoint), settings);
    final connectionBudget = operation.remainingSynthesisTime();
    final handshakeClient = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: connectionBudget < _networkIdleTimeout
          ? connectionBudget
          : _networkIdleTimeout,
    );
    operation.registerHttpClient(handshakeClient);
    WebSocket? ws;
    try {
      final remaining = operation.remainingSynthesisTime();
      ws = await operation.acquireWebSocket(
        WebSocket.connect('$uri', customClient: handshakeClient),
        timeout: remaining,
        onTimeout: () => handshakeClient.close(force: true),
      );
      final activeWebSocket = ws;
      final audioBytes = BytesBuilder(copy: false);
      activeWebSocket.add(
        jsonEncode(<String, Object?>{
          'common': <String, Object?>{'app_id': settings.appId},
          'business': <String, Object?>{
            'aue': '${settings.extra['aue'] ?? 'lame'}',
            'auf': '${settings.extra['auf'] ?? kAudioL16Rate16000}',
            'vcn': settings.voice.isEmpty ? 'xiaoyan' : settings.voice,
            'speed': settings.speed.round().clamp(0, 100),
            'volume': settings.volume.round().clamp(0, 100),
            'pitch': settings.pitch.round().clamp(0, 100),
            'tte': 'UTF8',
          },
          'data': <String, Object?>{
            'status': 2,
            'text': base64Encode(utf8.encode(text)),
          },
        }),
      );

      Future<void> consumeEvents() async {
        final remaining = operation.remainingSynthesisTime();
        final idleTimeout = remaining < _networkIdleTimeout
            ? remaining
            : _networkIdleTimeout;
        await for (final event in activeWebSocket.timeout(idleTimeout)) {
          operation.throwIfCancelled();
          if (event is String) {
            if (event.length > _maxWebSocketEventChars) {
              throw const FormatException('讯飞 TTS 事件超过安全上限。');
            }
            final decoded = _decodeTtsJson(
              event,
              maxTextCodeUnits: _maxWebSocketEventChars,
            );
            if (decoded is! Map) continue;
            final code = decoded['code'];
            if (code is int && code != 0) {
              throw StateError('讯飞 TTS 调用失败：${decoded['message'] ?? code}');
            }
            final data = decoded['data'];
            if (data is Map) {
              final audio = data['audio'];
              if (audio is String && audio.isNotEmpty) {
                _appendBoundedBase64Audio(
                  audioBytes,
                  audio,
                  maxBytes: _maxAudioResponseBytes,
                );
              }
              if (data['status'] == 2) return;
            }
          } else if (event is List<int> &&
              event.length > _maxWebSocketEventChars) {
            throw const FormatException('讯飞 TTS 事件超过安全上限。');
          }
        }
      }

      final totalRemaining = operation.remainingSynthesisTime();
      await consumeEvents().timeout(
        totalRemaining,
        onTimeout: () =>
            throw TimeoutException('讯飞 TTS 超过总时限。', totalRemaining),
      );
      operation.throwIfCancelled();
      return _AiTtsAudioPayload(
        audioBytes.takeBytes(),
        extension: '${settings.extra['aue'] ?? 'mp3'}' == 'raw'
            ? '.pcm'
            : '.mp3',
      );
    } finally {
      final activeWebSocket = ws;
      if (activeWebSocket != null) {
        await operation.releaseWebSocket(activeWebSocket);
      }
      operation.releaseHttpClient(handshakeClient);
    }
  }

  Future<_AiTtsAudioPayload> _synthesizeWithBaidu(
    AiTtsProviderSettings settings,
    String text, {
    required _AiTtsOperation operation,
  }) async {
    final accessToken = settings.accessToken.isNotEmpty
        ? settings.accessToken
        : await _fetchBaiduAccessToken(settings, operation: operation);
    final endpoint = _endpointOrDefault(settings);
    final uri = Uri.parse(endpoint).replace(
      queryParameters: <String, String>{
        'tex': text,
        'tok': accessToken,
        'cuid': 'openhand',
        'ctp': '1',
        'lan': settings.language.isEmpty ? 'zh' : settings.language,
        'spd': '${settings.speed.round().clamp(0, 15)}',
        'pit': '${settings.pitch.round().clamp(0, 15)}',
        'vol': '${settings.volume.round().clamp(0, 15)}',
        'per': settings.voice.isEmpty ? '0' : settings.voice,
        'aue': '3',
      },
    );
    final response = await operation.transport.get(
      uri: uri,
      headers: const <String, String>{HttpHeaders.acceptHeader: 'audio/*'},
      timeout: operation.remainingSynthesisTime(),
      maxResponseBytes: _maxAudioResponseBytes,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw HttpException('百度 TTS 请求失败（HTTP ${response.statusCode}）', uri: uri);
    }
    final contentType = response.headers[kContentTypeHeaderName] ?? '';
    if (!isAudioMimeType(contentType)) {
      throw StateError('百度 TTS 返回了非音频响应。');
    }
    operation.throwIfCancelled();
    return _AiTtsAudioPayload(response.bodyBytes, extension: '.mp3');
  }

  Future<_AiTtsAudioPayload> _synthesizeWithGoogle(
    AiTtsProviderSettings settings,
    String text, {
    required _AiTtsOperation operation,
  }) async {
    if (settings.apiKey.isEmpty) {
      throw StateError('Google TTS API 密钥不能为空。');
    }
    final endpoint = _endpointOrDefault(settings);
    final uri = Uri.parse(endpoint).replace(
      queryParameters: <String, String>{
        ...Uri.parse(endpoint).queryParameters,
        'key': settings.apiKey,
      },
    );
    final audioEncoding = _extraString(
      settings,
      'audioEncoding',
      fallback: 'MP3',
    );
    final response = await operation.transport.sendJson(
      uri: uri,
      method: 'POST',
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: kApplicationJsonUtf8ContentType,
        HttpHeaders.acceptHeader: kApplicationJsonMimeType,
      },
      body: <String, Object?>{
        'input': <String, Object?>{'text': text},
        'voice': <String, Object?>{
          'languageCode': settings.language.isEmpty
              ? 'zh-CN'
              : settings.language,
          if (settings.voice.isNotEmpty) 'name': settings.voice,
        },
        'audioConfig': <String, Object?>{
          'audioEncoding': audioEncoding,
          'speakingRate': settings.speed.clamp(0.25, 4.0),
          'pitch': settings.pitch.clamp(-20.0, 20.0),
          'volumeGainDb': settings.volume.clamp(-96.0, 16.0),
        },
      },
      timeout: operation.remainingSynthesisTime(),
      maxResponseBytes: _maxAudioJsonResponseBytes,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw HttpException(
        'Google TTS 请求失败（HTTP ${response.statusCode}）：${_shortBody(response)}',
        uri: uri,
      );
    }
    final decoded = _decodeTtsJson(
      response.body,
      maxTextCodeUnits: _maxAudioJsonResponseBytes,
    );
    if (decoded is! Map || decoded['audioContent'] is! String) {
      throw StateError('Google TTS 返回了无效音频数据。');
    }
    operation.throwIfCancelled();
    return _AiTtsAudioPayload(
      _decodeBoundedAudioBase64(
        decoded['audioContent'] as String,
        maxBytes: _maxAudioResponseBytes,
      ),
      extension: _googleAudioExtension(audioEncoding),
    );
  }

  Future<_AiTtsAudioPayload> _synthesizeWithBing(
    AiTtsProviderSettings settings,
    String text, {
    required _AiTtsOperation operation,
  }) async {
    if (settings.apiKey.isEmpty) {
      throw StateError('Bing TTS 订阅密钥不能为空。');
    }
    final region = nullIfBlank(settings.region);
    final configuredEndpoint = nullIfBlank(settings.endpoint);
    if (region == null && configuredEndpoint == null) {
      throw StateError('Bing TTS 区域不能为空。');
    }
    final endpoint =
        configuredEndpoint ??
        'https://$region.tts.speech.microsoft.com/cognitiveservices/v1';
    final uri = Uri.parse(endpoint);
    final outputFormat = _extraString(
      settings,
      'outputFormat',
      fallback: 'audio-24khz-48kbitrate-mono-mp3',
    );
    final response = await operation.transport.sendText(
      uri: uri,
      method: 'POST',
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: kApplicationSsmlXmlMimeType,
        HttpHeaders.acceptHeader: 'audio/*',
        'Ocp-Apim-Subscription-Key': settings.apiKey,
        'X-Microsoft-OutputFormat': outputFormat,
        HttpHeaders.userAgentHeader: 'OpenHand',
      },
      body: _bingSsml(text, settings),
      timeout: operation.remainingSynthesisTime(),
      maxResponseBytes: _maxAudioResponseBytes,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw HttpException(
        'Bing TTS 请求失败（HTTP ${response.statusCode}）：${_shortBody(response)}',
        uri: uri,
      );
    }
    operation.throwIfCancelled();
    return _AiTtsAudioPayload(
      response.bodyBytes,
      extension: _bingAudioExtension(outputFormat),
    );
  }

  Future<_AiTtsAudioPayload> _synthesizeWithYoudao(
    AiTtsProviderSettings settings,
    String text, {
    required _AiTtsOperation operation,
  }) async {
    if (settings.apiKey.isEmpty || settings.apiSecret.isEmpty) {
      throw StateError('有道 TTS 凭据不完整。');
    }
    final endpoint = _endpointOrDefault(settings);
    final salt = DateTime.now().microsecondsSinceEpoch.toString();
    final input = _youdaoSignInput(text);
    final curtime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sign = sha256
        .convert(
          utf8.encode(
            '${settings.apiKey}$input$salt$curtime${settings.apiSecret}',
          ),
        )
        .toString();
    final uri = Uri.parse(endpoint);
    final response = await operation.transport.sendForm(
      uri: uri,
      method: 'POST',
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader:
            '$kFormUrlEncodedMimeType; charset=utf-8',
      },
      body: <String, String>{
        'q': text,
        'langType': settings.language.isEmpty ? 'zh-CHS' : settings.language,
        'appKey': settings.apiKey,
        'salt': salt,
        'sign': sign,
        'signType': 'v3',
        'curtime': '$curtime',
        if (settings.voice.isNotEmpty) 'voice': settings.voice,
        'format': 'mp3',
      },
      timeout: operation.remainingSynthesisTime(),
      maxResponseBytes: _maxAudioResponseBytes,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw HttpException(
        '有道 TTS 请求失败（HTTP ${response.statusCode}）：${_shortBody(response)}',
        uri: uri,
      );
    }
    final contentType = response.headers[kContentTypeHeaderName] ?? '';
    if (!isAudioMimeType(contentType)) {
      throw StateError('有道 TTS 返回了非音频响应。');
    }
    operation.throwIfCancelled();
    return _AiTtsAudioPayload(response.bodyBytes, extension: '.mp3');
  }

  Future<void> _playAudioBytes(
    List<int> bytes, {
    required String extension,
    required double volume,
    required AiTtsProviderSettings provider,
    required Duration requestTimeout,
    required _AiTtsOperation operation,
    required bool Function() isCurrent,
  }) {
    return operation.runTrackedActivity(() async {
      if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
      if (bytes.isEmpty) throw StateError('TTS 返回了空音频。');
      if (!Platform.isMacOS) {
        throw UnsupportedError('音频播放当前仅支持 macOS。');
      }
      final dir = Directory(
        p.join(OpenHandPaths.defaultCacheDirectoryPath(), 'tts'),
      );
      await (_stalePlaybackCleanupFuture ??= _cleanupStalePlaybackFiles(dir));
      final file = File(
        p.join(
          dir.path,
          'tts_${DateTime.now().microsecondsSinceEpoch}_${_tempFileSerial++}$extension',
        ),
      );
      BoundedRandomAccessFileLease? output;
      var deleteOnRelease = true;
      try {
        await dir.create(recursive: true).timeout(_playbackFileIoTimeout);
        final openedFile = await operation.acquireFile(
          file.open(mode: FileMode.writeOnly),
          timeout: _playbackFileIoTimeout,
          deleteIfAcquisitionCompletesLate: file,
        );
        final openedOutput = BoundedRandomAccessFileLease(
          openedFile,
          release: (activeFile) async {
            try {
              // 刷盘完成后同步关闭，规避 macOS 异步 close 偶发不完成。
              operation.releaseFileSynchronously(activeFile);
            } finally {
              if (deleteOnRelease) await _deletePlaybackFileSilently(file);
            }
          },
        );
        output = openedOutput;
        await openedOutput.run<void>((activeFile) async {
          await activeFile.writeFrom(bytes);
        }, timeout: _playbackFileIoTimeout);
        await openedOutput.run<void>((activeFile) async {
          await activeFile.flush();
        }, timeout: _playbackFileIoTimeout);
        deleteOnRelease = false;
        try {
          await openedOutput.close(timeout: _playbackFileIoTimeout);
        } catch (_) {
          deleteOnRelease = true;
          rethrow;
        }
        output = null;
        operation.throwIfCancelled();
        if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
        final playbackTimeout = await _playbackTimeoutForAudioFile(
          file,
          byteLength: bytes.length,
          extension: extension,
          provider: provider,
          requestTimeout: requestTimeout,
        );
        operation.throwIfCancelled();
        if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
        await _playAudioFile(
          file.path,
          volume: volume,
          timeout: playbackTimeout,
          operation: operation,
        );
      } finally {
        deleteOnRelease = output != null;
        await output?.cleanup();
        if (output == null) {
          await _deletePlaybackFileSilently(file);
        }
      }
    });
  }

  static Future<void> _deletePlaybackFileSilently(File file) async {
    try {
      if (await file.exists().timeout(_resourceCloseTimeout)) {
        await file.delete().timeout(_resourceCloseTimeout);
      }
    } catch (_) {
      // 缓存清理仅尽力执行，不能覆盖播放失败。
    }
  }

  Future<void> _cleanupStalePlaybackFiles(Directory directory) async {
    final deadline = MonotonicDeadline(
      _stalePlaybackCleanupTimeout,
      timeoutMessage: 'TTS 过期文件清理超时。',
    );
    final iterator = StreamIterator<FileSystemEntity>(
      directory.list(followLinks: false),
    );

    var scanned = 0;
    var deleted = 0;
    final staleBefore = DateTime.now().subtract(_stalePlaybackFileAge);
    try {
      while (scanned < _stalePlaybackScanLimit &&
          deleted < _stalePlaybackDeleteLimit &&
          await iterator.moveNext().timeout(deadline.remaining())) {
        scanned += 1;
        final entity = iterator.current;
        if (entity is! File || !p.basename(entity.path).startsWith('tts_')) {
          continue;
        }
        final stat = await entity.stat().timeout(deadline.remaining());
        if (stat.type != FileSystemEntityType.file ||
            !stat.modified.isBefore(staleBefore)) {
          continue;
        }
        await entity.delete().timeout(deadline.remaining());
        deleted += 1;
      }
    } catch (_) {
      // 启动清理仅尽力执行，并受严格时限约束。
    } finally {
      deadline.stop();
      await runAsyncCleanupBounded(iterator.cancel);
    }
  }

  Future<void> _playAudioFile(
    String path, {
    required double volume,
    required Duration timeout,
    required _AiTtsOperation operation,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('音频播放当前仅支持 macOS。');
    }
    final file = File(path);
    final metadataTimeout = timeout < _playbackFileIoTimeout
        ? timeout
        : _playbackFileIoTimeout;
    if (!await file.exists().timeout(metadataTimeout)) {
      throw StateError('TTS 音频文件不存在。');
    }
    operation.throwIfCancelled();
    await _runSpeechProcess(
      'afplay',
      <String>['-v', '${_unitPlaybackVolume(volume)}', file.path],
      timeout: timeout,
      operation: operation,
    );
  }

  Future<Duration> _playbackTimeoutForAudioFile(
    File file, {
    required int byteLength,
    required String extension,
    required AiTtsProviderSettings provider,
    required Duration requestTimeout,
  }) async {
    final probedDuration = await _probeAudioDuration(file.path);
    final estimatedDuration =
        probedDuration ??
        _estimateAudioDurationFromBytes(
          byteLength: byteLength,
          extension: extension,
          provider: provider,
        );
    return _audibleProcessTimeout(
      estimatedDuration,
      requestTimeout: requestTimeout,
    );
  }

  Future<Duration?> _probeAudioDuration(String path) async {
    if (!Platform.isMacOS) return null;
    try {
      final result = await runTrackedProcessOrFailed(
        'afinfo',
        <String>[path],
        timeout: _audioDurationProbeTimeout,
        tag: 'ai_tts.audio_duration',
      );
      if (result.exitCode != 0) return null;
      return _parseAfinfoDuration('${result.stdout}\n${result.stderr}');
    } catch (error, stack) {
      silentLog('ai_tts_playback_service', '探测音频时长', error, stack);
      return null;
    }
  }

  Future<_AiTtsAudioPayload> _audioPayloadFromReference(
    String reference, {
    required String outputFormat,
    required _AiTtsOperation operation,
  }) async {
    final normalized = reference.trim();
    if (normalized.isEmpty) {
      throw StateError('TTS 音频引用不能为空。');
    }
    final uri = Uri.tryParse(normalized);
    if (uri != null && uri.hasScheme) {
      if (uri.scheme == 'file') {
        return _audioPayloadFromFile(
          uri.toFilePath(),
          outputFormat: outputFormat,
          operation: operation,
        );
      }
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return _remoteAudioPayload(
          uri,
          outputFormat: outputFormat,
          operation: operation,
        );
      }
      throw StateError('AI TTS 返回了不支持的音频引用。');
    }
    return _audioPayloadFromFile(
      normalized,
      outputFormat: outputFormat,
      operation: operation,
    );
  }

  Future<_AiTtsAudioPayload> _audioPayloadFromFile(
    String path, {
    required String outputFormat,
    required _AiTtsOperation operation,
  }) async {
    final file = File(path);
    final remaining = operation.remainingSynthesisTime();
    final bytes = await operation.runTrackedActivity(
      () => readBoundedFileBytes(
        file,
        maxBytes: _maxAudioResponseBytes,
        idleTimeout: remaining < _fileReadIdleTimeout
            ? remaining
            : _fileReadIdleTimeout,
        totalTimeout: remaining,
        handleOwner: operation,
      ),
    );
    operation.throwIfCancelled();
    return _AiTtsAudioPayload(
      bytes,
      extension: _audioExtensionFromPath(path, fallbackFormat: outputFormat),
    );
  }

  Future<_AiTtsAudioPayload> _remoteAudioPayload(
    Uri uri, {
    required String outputFormat,
    required _AiTtsOperation operation,
  }) async {
    final response = await operation.transport.get(
      uri: uri,
      headers: const <String, String>{HttpHeaders.acceptHeader: 'audio/*'},
      timeout: operation.remainingSynthesisTime(),
      maxResponseBytes: _maxAudioResponseBytes,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw HttpException(
        'AI TTS 音频下载失败（HTTP ${response.statusCode}）',
        uri: uri,
      );
    }
    final contentType = _responseContentType(response.headers);
    if (!_isPlayableAudioContentType(contentType)) {
      throw StateError('AI TTS 音频地址返回了非音频内容。');
    }
    operation.throwIfCancelled();
    return _AiTtsAudioPayload(
      response.bodyBytes,
      extension: _audioExtensionFromUri(uri, fallbackFormat: outputFormat),
    );
  }

  Future<void> _runSpeechProcess(
    String executable,
    List<String> args, {
    required Duration timeout,
    required _AiTtsOperation operation,
  }) async {
    final processStartTimeout = timeout < _speechProcessStartTimeout
        ? timeout
        : _speechProcessStartTimeout;
    final process = await operation.acquireProcess(
      startTrackedProcessBounded(
        executable,
        args,
        timeout: processStartTimeout,
        tag: 'ai_tts_playback_service',
        startInNewProcessGroup: true,
      ),
    );
    final stderrBuffer = StringBuffer();
    final stderrSubscription = process.stderr.transform(utf8.decoder).listen((
      chunk,
    ) {
      const maxChars = 1000;
      final remaining = maxChars - stderrBuffer.length;
      if (remaining <= 0) return;
      stderrBuffer.write(
        chunk.length <= remaining
            ? chunk
            : chunk.substring(0, safeUtf16PrefixCodeUnits(chunk, remaining)),
      );
    }, onError: (Object _, StackTrace _) {});
    final stdoutSubscription = process.stdout.listen(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      operation.throwIfCancelled();
      if (exitCode != 0) {
        final stderrText = stderrBuffer.toString().trim();
        throw ProcessException(
          executable,
          const <String>[],
          stderrText.isEmpty
              ? 'TTS 进程退出码：$exitCode'
              : 'TTS 进程退出码：$exitCode；$stderrText',
          exitCode,
        );
      }
    } on TimeoutException {
      final cancelled = operation.isCancelled;
      await operation.terminateProcess(process);
      if (cancelled) throw const _AiTtsPlaybackCancelled();
      throw TimeoutException('TTS 进程执行超时。', timeout);
    } finally {
      operation.unregisterProcess(process);
      await Future.wait<void>(<Future<void>>[
        _cancelTtsSubscription(stderrSubscription),
        _cancelTtsSubscription(stdoutSubscription),
      ]);
    }
  }

  static Future<void> _cancelTtsSubscription<T>(
    StreamSubscription<T> subscription,
  ) async {
    await cancelStreamSubscriptionBounded<T>(
      subscription,
      timeout: _speechProcessPipeDrainTimeout,
    );
  }

  Uri _xfyunAuthorizedUri(Uri endpoint, AiTtsProviderSettings settings) {
    final date = HttpDate.format(DateTime.now().toUtc());
    final host = endpoint.host;
    final path = endpoint.path.isEmpty ? '/v2/tts' : endpoint.path;
    final signatureOrigin = 'host: $host\ndate: $date\nGET $path HTTP/1.1';
    final signatureSha = Hmac(
      sha256,
      utf8.encode(settings.apiSecret),
    ).convert(utf8.encode(signatureOrigin));
    final authorizationOrigin =
        'api_key="${settings.apiKey}", algorithm="hmac-sha256", headers="host date request-line", signature="${base64Encode(signatureSha.bytes)}"';
    return endpoint.replace(
      queryParameters: <String, String>{
        ...endpoint.queryParameters,
        'authorization': base64Encode(utf8.encode(authorizationOrigin)),
        'date': date,
        'host': host,
      },
    );
  }

  Future<String> _fetchBaiduAccessToken(
    AiTtsProviderSettings settings, {
    required _AiTtsOperation operation,
  }) async {
    if (settings.apiKey.isEmpty || settings.apiSecret.isEmpty) {
      throw StateError('百度 TTS API 密钥或密文不能为空。');
    }
    final uri = Uri.parse('https://aip.baidubce.com/oauth/2.0/token').replace(
      queryParameters: <String, String>{
        'grant_type': 'client_credentials',
        'client_id': settings.apiKey,
        'client_secret': settings.apiSecret,
      },
    );
    final response = await operation.transport.sendText(
      uri: uri,
      method: 'POST',
      headers: const <String, String>{},
      body: '',
      timeout: operation.remainingSynthesisTime(),
      maxResponseBytes: _maxControlResponseBytes,
    );
    if (isHttpFailureStatus(response.statusCode)) {
      throw HttpException(
        '百度 TTS 令牌请求失败（HTTP ${response.statusCode}）：${_shortBody(response)}',
        uri: uri,
      );
    }
    final decoded = _decodeTtsJson(
      response.body,
      maxTextCodeUnits: _maxControlResponseBytes,
    );
    if (decoded is! Map || decoded['access_token'] is! String) {
      throw StateError('百度 TTS 令牌响应无效。');
    }
    operation.throwIfCancelled();
    return decoded['access_token'] as String;
  }

  Future<String> _resolveMacOsVoice(String configuredVoice) async {
    final normalized = _macOsVoiceAlias(configuredVoice.trim());
    if (normalized.isEmpty || !Platform.isMacOS) return '';
    late final Set<String> voices;
    try {
      voices = await _macOsVoiceNamesCache.load();
    } catch (error, stack) {
      silentLog('ai_tts_playback_service', '加载 macOS 语音名称', error, stack);
      return '';
    }
    if (voices.contains(normalized)) return normalized;
    final lower = normalized.toLowerCase();
    for (final voice in voices) {
      if (voice.toLowerCase() == lower) return voice;
    }
    return '';
  }

  Future<Set<String>> _loadMacOsVoiceNames() async {
    final result = await runTrackedProcessOrFailed(
      'say',
      const <String>['-v', '?'],
      timeout: const Duration(seconds: 2),
      tag: 'ai_tts.load_voices',
    );
    if (result.exitCode != 0) {
      throw StateError('macOS 语音清单命令执行失败，退出码：${result.exitCode}。');
    }
    final output = '${result.stdout}';
    return trimmedNonEmptyStrings(
      output
          .split('\n')
          .map(
            (line) =>
                line.trimLeft().split(_macOsVoiceColumnSeparatorPattern).first,
          ),
    ).toSet();
  }

  static String _normalizeText(String text, int maxCharacters) {
    final trimmed = collapseInlineWhitespace(
      stripHtmlTags(text.replaceAll(_markdownCodeBlockPattern, ' ')),
    );
    return clipText(trimmed, maxCharacters, suffix: '');
  }

  static String _firstMediaReference(String markdown) {
    final match = _markdownMediaLinkPattern.firstMatch(markdown);
    final raw = _cleanMediaReference(match?.group(1) ?? '');
    if (raw.isNotEmpty) return raw;
    for (final line in markdown.split('\n')) {
      final candidate = _cleanMediaReference(line);
      if (_looksLikeMediaReference(candidate)) return candidate;
    }
    return '';
  }

  static String _cleanMediaReference(String raw) {
    var value = raw.trim();
    if (value.startsWith('<') && value.endsWith('>') && value.length > 2) {
      value = value.substring(1, value.length - 1).trim();
    }
    final titleIndex = value.indexOf(_markdownLinkTitlePattern);
    if (titleIndex > 0) {
      value = value.substring(0, titleIndex).trim();
    }
    return value;
  }

  static bool _looksLikeMediaReference(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return false;
    final uri = Uri.tryParse(normalized);
    if (uri != null && uri.hasScheme) {
      return uri.scheme == 'file' ||
          uri.scheme == 'http' ||
          uri.scheme == 'https';
    }
    return normalized.startsWith('/') ||
        normalized.contains(Platform.pathSeparator);
  }

  static int _systemRate(double speed) {
    if (speed > 10) return speed.round().clamp(80, 420);
    return (175 * speed.clamp(0.5, 2.0)).round();
  }

  static String _macOsSpeechScript(
    String text,
    AiTtsProviderSettings settings,
  ) {
    final buffer = StringBuffer('say ${_appleScriptString(text)}');
    buffer
      ..write(' speaking rate ${_systemRate(settings.speed)}')
      ..write(' pitch ${_systemPitch(settings.pitch)}')
      ..write(' volume ${_systemVolume(settings.volume)}');
    return buffer.toString();
  }

  static int _systemPitch(double pitch) {
    if (pitch > 10) return pitch.round().clamp(0, 100);
    return (50 * pitch.clamp(0.5, 2.0)).round().clamp(0, 100);
  }

  static String _macOsVoiceAlias(String voice) {
    switch (voice) {
      case 'Mei-Jia':
        return 'Meijia';
      case 'Sin-ji':
        return 'Sinji';
      default:
        return voice;
    }
  }

  static double _systemVolume(double volume) {
    if (!volume.isFinite) return 1.0;
    return volume <= 1
        ? clampUnitInterval(volume)
        : clampUnitInterval(volume / 100);
  }

  static Duration _speechProcessTimeoutForText(
    String text,
    AiTtsProviderSettings settings, {
    required Duration requestTimeout,
  }) {
    final characterCount = math.max(1, text.runes.length);
    final charsPerMinute =
        (_defaultSpeechCharsPerMinute * _speechSpeedFactor(settings.speed))
            .round()
            .clamp(_minSpeechCharsPerMinute, _maxSpeechCharsPerMinute)
            .toInt();
    final estimatedMs = (characterCount * 60000 / charsPerMinute).ceil();
    return _audibleProcessTimeout(
      Duration(milliseconds: estimatedMs),
      requestTimeout: requestTimeout,
    );
  }

  static double _speechSpeedFactor(double speed) {
    if (!speed.isFinite) return 1.0;
    if (speed > 10) {
      return (_systemRate(speed) / 175).clamp(0.45, 2.4).toDouble();
    }
    return speed.clamp(0.5, 2.0).toDouble();
  }

  static Duration _estimateAudioDurationFromBytes({
    required int byteLength,
    required String extension,
    required AiTtsProviderSettings provider,
  }) {
    final normalizedExtension = lowercaseStringFromValue(extension);
    if (normalizedExtension == '.wav' || normalizedExtension == '.pcm') {
      final sampleRate = _extraInt(
        provider,
        'sample_rate',
        fallback: _defaultAiTtsSampleRate,
      ).clamp(8000, 96000).toInt();
      final channels = _extraInt(
        provider,
        'channels',
        fallback: 1,
      ).clamp(1, 2).toInt();
      final headerBytes = normalizedExtension == '.wav' ? 44 : 0;
      final payloadBytes = math.max(0, byteLength - headerBytes);
      final bytesPerSecond = sampleRate * channels * _pcm16BytesPerSample;
      return _durationFromSeconds(payloadBytes / bytesPerSecond);
    }
    final bitRate = _estimatedCompressedAudioBitRate(provider);
    return _durationFromSeconds(byteLength * 8 / bitRate);
  }

  static int _estimatedCompressedAudioBitRate(AiTtsProviderSettings settings) {
    final configuredBitRate = _extraInt(settings, 'bit_rate', fallback: 0);
    final outputFormatBitRate = _bitRateFromText(
      _extraString(settings, 'outputFormat'),
    );
    final selectedBitRate = configuredBitRate > 0
        ? configuredBitRate
        : outputFormatBitRate ?? _conservativeCompressedAudioBitRate;
    return math
        .min(selectedBitRate, _conservativeCompressedAudioBitRate)
        .clamp(_minCompressedAudioBitRate, _maxCompressedAudioBitRate)
        .toInt();
  }

  static int? _bitRateFromText(String value) {
    final match = _audioBitRatePattern.firstMatch(value);
    if (match == null) return null;
    final kbps = optionalPositiveIntFromValue(match.group(1));
    if (kbps == null) return null;
    return kbps * 1000;
  }

  static Duration? _parseAfinfoDuration(String output) {
    final match = _afinfoDurationPattern.firstMatch(output);
    if (match == null) return null;
    final seconds = optionalPositiveDoubleFromValue(match.group(1));
    if (seconds == null) return null;
    return _durationFromSeconds(seconds);
  }

  static Duration _durationFromSeconds(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return Duration.zero;
    return Duration(milliseconds: (seconds * 1000).ceil());
  }

  static Duration _audibleProcessTimeout(
    Duration estimatedDuration, {
    required Duration requestTimeout,
  }) {
    final baselineMs = math.max(
      estimatedDuration.inMilliseconds,
      requestTimeout.inMilliseconds,
    );
    final graceMs = math.max(
      _audiblePlaybackGrace.inMilliseconds,
      (baselineMs * _audiblePlaybackGraceRatio).ceil(),
    );
    return _clampDuration(
      Duration(milliseconds: baselineMs + graceMs),
      min: _audiblePlaybackMinTimeout,
      max: _audiblePlaybackMaxTimeout,
    );
  }

  static Duration _clampDuration(
    Duration value, {
    required Duration min,
    required Duration max,
  }) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static int _linuxRate(double speed) {
    if (speed > 10) return ((speed - 50) * 2).round().clamp(-100, 100);
    return ((speed - 1.0) * 100).round().clamp(-100, 100);
  }

  static void _handleDoubaoPayload(
    String payload, {
    required void Function(String audioBase64) onAudio,
  }) {
    final decoded = _decodeTtsJson(
      payload,
      maxTextCodeUnits: _maxDoubaoFrameChars,
    );
    if (decoded is! Map) return;
    final code = decoded['code'];
    if (code is int && code != 0 && code != _doubaoTtsSuccessCode) {
      throw StateError('豆包 TTS 调用失败：${decoded['message'] ?? code}');
    }
    if (code == _doubaoTtsSuccessCode) return;
    final data = decoded['data'];
    if (data is String && data.isNotEmpty) {
      onAudio(data);
      return;
    }
    if (data is Map) {
      final audio = data['audio'] ?? data['data'];
      if (audio is String && audio.isNotEmpty) onAudio(audio);
    }
  }

  static Uint8List _decodeBoundedAudioBase64(
    String encoded, {
    required int maxBytes,
  }) {
    if (maxBytes < 1) {
      throw StateError('TTS 音频超过配置的安全上限。');
    }
    try {
      return decodeBase64Bounded(encoded, maxDecodedBytes: maxBytes);
    } on BoundedBase64SizeException {
      throw StateError('TTS 音频超过 ${formatByteSize(maxBytes)} 的安全上限。');
    } on BoundedBase64FormatException {
      throw const FormatException('TTS 音频 Base64 格式无效。');
    }
  }

  static Object? _decodeTtsJson(String text, {required int maxTextCodeUnits}) {
    return decodeJsonTextUsingConfig(
      text,
      maxTextCodeUnits: maxTextCodeUnits,
      config: _jsonConversionConfig,
    );
  }

  static void _appendBoundedBase64Audio(
    BytesBuilder destination,
    String encoded, {
    required int maxBytes,
  }) {
    final remaining = maxBytes - destination.length;
    final decoded = _decodeBoundedAudioBase64(encoded, maxBytes: remaining);
    destination.add(decoded);
  }

  static Future<void> _closeWebSocketBounded(WebSocket socket) async {
    try {
      await socket.close().timeout(_resourceCloseTimeout);
    } catch (_) {
      // 操作自有的 HttpClient 由其所有者强制关闭。
    }
  }

  static Uint8List _decodeMimoAudioPayload(Map<String, Object?> input) {
    final body = input['body'];
    final format = '${input['format'] ?? 'wav'}';
    final sampleRate = input['sample_rate'] is int
        ? input['sample_rate'] as int
        : 24000;
    final maxAudioBytes = input['max_audio_bytes'] is int
        ? input['max_audio_bytes'] as int
        : _maxAudioResponseBytes;
    if (body is! String || nullIfBlank(body) == null) {
      throw StateError('Mimo TTS 返回了空响应。');
    }
    final Object? decoded;
    try {
      decoded = _decodeTtsJson(
        body,
        maxTextCodeUnits: _maxAudioJsonResponseBytes,
      );
    } on FormatException catch (error) {
      throw StateError('Mimo TTS 返回了无效 JSON：${error.message}');
    }
    final businessError = _mimoBusinessError(decoded);
    if (businessError != null) {
      throw StateError('Mimo TTS 调用失败：$businessError');
    }
    final pcm16 = _isPcm16Format(format);
    final encoded = _chatCompletionAudioData(decoded, providerName: 'Mimo TTS');
    final Uint8List bytes;
    try {
      bytes = _decodeBoundedAudioBase64(
        _base64AudioData(encoded),
        maxBytes: pcm16 ? maxAudioBytes - _minimumWavBytes : maxAudioBytes,
      );
    } on FormatException {
      throw StateError('Mimo TTS 返回了无效 Base64 音频。');
    }
    if (pcm16) {
      _validatePcm16Audio(bytes, providerName: 'Mimo TTS');
      return _wavBytesFromPcm16(bytes, sampleRate: sampleRate);
    }
    final normalizedFormat = lowercaseStringFromValue(format);
    if (normalizedFormat == 'wav') {
      _validateMimoWavAudio(bytes);
    } else if (normalizedFormat == 'mp3') {
      _validateMimoMp3Audio(bytes);
    }
    return bytes;
  }

  static String _chatCompletionAudioData(
    Object? decoded, {
    required String providerName,
  }) {
    if (decoded is Map) {
      final audio = decoded['audio'];
      final topLevel = _audioDataFromObject(audio);
      if (topLevel != null) return topLevel;

      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        for (final choice in choices) {
          if (choice is! Map) continue;
          final message = choice['message'];
          final fromMessage = message is Map
              ? _audioDataFromObject(message['audio'])
              : null;
          if (fromMessage != null) return fromMessage;
          final delta = choice['delta'];
          final fromDelta = delta is Map
              ? _audioDataFromObject(delta['audio'])
              : null;
          if (fromDelta != null) return fromDelta;
        }
      }
    }
    throw StateError('$providerName 返回了无效音频数据。');
  }

  static String? _audioDataFromObject(Object? audio) {
    if (audio is String) return optionalStringFromValue(audio);
    if (audio is! Map) return null;
    final data = audio['data'] ?? audio['audio'] ?? audio['audio_data'];
    return optionalStringFromValue(data);
  }

  static String? _mimoBusinessError(Object? decoded) {
    if (decoded is! Map) return null;
    final error = decoded['error'];
    if (error != null) {
      return extractApiErrorMessage(
        jsonEncode(<String, Object?>{'error': error}),
        maxLength: 500,
        emptyFallback: '未知服务错误',
      );
    }
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) return null;
    final message =
        optionalStringFromValue(decoded['message']) ??
        optionalStringFromValue(decoded['msg']) ??
        optionalStringFromValue(decoded['detail']);
    final code = optionalStringFromValue(decoded['code']);
    if (message == null && code == null) return null;
    return <String>[
      if (code != null) code,
      if (message != null) message,
    ].join(': ');
  }

  static String _base64AudioData(String value) {
    final normalized = value.trim();
    if (!normalized.toLowerCase().startsWith('data:')) return normalized;
    final separator = normalized.indexOf(',');
    final metadata = separator < 0
        ? ''
        : normalized.substring(0, separator).toLowerCase();
    if (separator < 0 || !metadata.contains(';base64')) {
      throw const FormatException('音频 Data URL 无效。');
    }
    return normalized.substring(separator + 1).trim();
  }

  static void _validatePcm16Audio(
    Uint8List bytes, {
    required String providerName,
  }) {
    if (bytes.length < _pcm16BytesPerSample || bytes.length.isOdd) {
      throw StateError('$providerName 返回了无效 PCM16 音频。');
    }
    final data = ByteData.sublistView(bytes);
    for (var offset = 0; offset < bytes.length; offset += 2) {
      if (data.getInt16(offset, Endian.little) != 0) return;
    }
    throw StateError('$providerName 返回了静音 PCM16 音频。');
  }

  static void _validateMimoWavAudio(Uint8List bytes) {
    if (bytes.length < _minimumWavBytes ||
        !_asciiEquals(bytes, 0, 'RIFF') ||
        !_asciiEquals(bytes, 8, 'WAVE')) {
      throw StateError('Mimo TTS 返回了无效 WAV 音频。');
    }
    final data = ByteData.sublistView(bytes);
    final riffEnd = data.getUint32(4, Endian.little) + 8;
    if (riffEnd < _minimumWavBytes || riffEnd > bytes.length) {
      throw StateError('Mimo TTS 返回了截断的 WAV 音频。');
    }
    var offset = 12;
    var pcmFormat = false;
    var blockAlign = 0;
    var bitsPerSample = 0;
    var dataOffset = -1;
    var dataLength = 0;
    while (offset + 8 <= riffEnd) {
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final chunkDataOffset = offset + 8;
      final chunkEnd = chunkDataOffset + chunkSize;
      if (chunkEnd > riffEnd) {
        throw StateError('Mimo TTS 返回了格式错误的 WAV 数据块。');
      }
      if (_asciiEquals(bytes, offset, 'fmt ')) {
        if (chunkSize < 16) {
          throw StateError('Mimo TTS 返回了无效 WAV 格式元数据。');
        }
        final formatTag = data.getUint16(chunkDataOffset, Endian.little);
        final channels = data.getUint16(chunkDataOffset + 2, Endian.little);
        final sampleRate = data.getUint32(chunkDataOffset + 4, Endian.little);
        final byteRate = data.getUint32(chunkDataOffset + 8, Endian.little);
        blockAlign = data.getUint16(chunkDataOffset + 12, Endian.little);
        bitsPerSample = data.getUint16(chunkDataOffset + 14, Endian.little);
        if (channels == 0 ||
            sampleRate == 0 ||
            byteRate == 0 ||
            blockAlign == 0 ||
            bitsPerSample == 0) {
          throw StateError('Mimo TTS 返回了不可用的 WAV 元数据。');
        }
        pcmFormat = formatTag == 1;
      } else if (_asciiEquals(bytes, offset, 'data') && chunkSize > 0) {
        dataOffset = chunkDataOffset;
        dataLength = chunkSize;
      }
      offset = chunkEnd + (chunkSize.isOdd ? 1 : 0);
    }
    if (blockAlign == 0 ||
        dataOffset < 0 ||
        dataLength < blockAlign ||
        dataLength % blockAlign != 0) {
      throw StateError('Mimo TTS 返回了空或不完整的 WAV 音频。');
    }
    if (pcmFormat && bitsPerSample == 16) {
      final audio = ByteData.sublistView(
        bytes,
        dataOffset,
        dataOffset + dataLength,
      );
      for (var sample = 0; sample < dataLength; sample += 2) {
        if (audio.getInt16(sample, Endian.little) != 0) return;
      }
      throw StateError('Mimo TTS 返回了静音 WAV 音频。');
    }
  }

  static void _validateMimoMp3Audio(Uint8List bytes) {
    if (bytes.length < 4) {
      throw StateError('Mimo TTS 返回了截断的 MP3 音频。');
    }
    final hasId3Header =
        bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
    final hasFrameSync = bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
    if (!hasId3Header && !hasFrameSync) {
      throw StateError('Mimo TTS 返回了无效 MP3 音频。');
    }
  }

  static bool _asciiEquals(Uint8List bytes, int offset, String value) {
    if (offset < 0 || offset + value.length > bytes.length) return false;
    for (var index = 0; index < value.length; index += 1) {
      if (bytes[offset + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  static bool _isPcm16Format(String format) {
    final normalized = lowercaseStringFromValue(format).replaceAll('_', '');
    return normalized == 'pcm' || normalized == 'pcm16';
  }

  static Uint8List _wavBytesFromPcm16(
    Uint8List pcmBytes, {
    required int sampleRate,
  }) {
    final safeSampleRate = sampleRate.clamp(8000, 96000).toInt();
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = safeSampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    final output = Uint8List(44 + pcmBytes.length);
    final header = ByteData.sublistView(output);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        output[offset + i] = value.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + pcmBytes.length, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, safeSampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, pcmBytes.length, Endian.little);
    output.setRange(44, output.length, pcmBytes);
    return output;
  }

  static String _audioExtension(String format) {
    switch (lowercaseStringFromValue(format)) {
      case 'aac':
        return '.aac';
      case 'flac':
        return '.flac';
      case 'pcm':
        return '.pcm';
      case 'opus':
        return '.opus';
      case 'wav':
        return '.wav';
      case 'ogg':
      case 'ogg_opus':
        return '.ogg';
      case 'mp3':
      default:
        return '.mp3';
    }
  }

  static String _audioExtensionFromUri(
    Uri uri, {
    required String fallbackFormat,
  }) {
    return _audioExtensionFromPath(uri.path, fallbackFormat: fallbackFormat);
  }

  static String _audioExtensionFromPath(
    String value, {
    required String fallbackFormat,
  }) {
    final path = value.toLowerCase();
    const supportedExtensions = <String>{
      '.aac',
      '.flac',
      '.m4a',
      '.mp3',
      '.ogg',
      '.opus',
      '.pcm',
      '.wav',
    };
    for (final extension in supportedExtensions) {
      if (path.endsWith(extension)) return extension;
    }
    return _audioExtension(fallbackFormat);
  }

  static String _responseContentType(Map<String, String> headers) {
    return (headers[HttpHeaders.contentTypeHeader] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
  }

  static bool _isPlayableAudioContentType(String contentType) {
    return contentType.isEmpty ||
        isAudioMimeType(contentType) ||
        contentType == kApplicationOctetStreamMimeType;
  }

  static String _mimoAudioExtension(String format) {
    if (_isPcm16Format(format)) return '.wav';
    return _audioExtension(format);
  }

  static bool _mimoUsesPresetVoice(String model) {
    final normalized = nullIfBlank(model);
    return normalized == null || normalized == 'mimo-v2.5-tts';
  }

  static bool _mimoUsesWavOutput(AiTtsProviderSettings settings) {
    return lowercaseStringFromValue(
          settings.extra['format'],
          fallback: aiMimoDefaultAudioFormat,
        ) !=
        'mp3';
  }

  static bool _mimoUsesVoiceClone(String model) {
    return nullIfBlank(model) == 'mimo-v2.5-tts-voiceclone';
  }

  static String _mimoStylePrompt(AiTtsProviderSettings settings) {
    final language = settings.language.trim();
    final style = _extraString(
      settings,
      'style_prompt',
      fallback: '自然清晰，语速适中，语气友好。',
    );
    final parts = trimmedNonEmptyStrings(<String>[
      if (language.isNotEmpty) '语言：$language',
      style,
      _mimoSpeedDirective(settings.speed),
      _mimoPitchDirective(settings.pitch),
    ]);
    return parts.join('；');
  }

  static String _mimoSpeedDirective(double speed) {
    if (speed < 0.85) return '语速稍慢';
    if (speed > 1.15) return '语速稍快';
    return '语速适中';
  }

  static String _mimoPitchDirective(double pitch) {
    if (pitch < 0.85) return '音调略低';
    if (pitch > 1.15) return '音调略高';
    return '音调自然';
  }

  static String? _mimoVoiceSampleMimeType(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.mp3':
        return kAudioMpegMimeType;
      case '.wav':
        return kAudioWavMimeType;
      default:
        return null;
    }
  }

  static String _googleAudioExtension(String encoding) {
    switch (encoding.trim().toUpperCase()) {
      case 'LINEAR16':
        return '.wav';
      case 'OGG_OPUS':
        return '.ogg';
      case 'MP3':
      default:
        return '.mp3';
    }
  }

  static String _bingAudioExtension(String outputFormat) {
    final normalized = lowercaseStringFromValue(outputFormat);
    if (normalized.startsWith('riff')) return '.wav';
    if (normalized.startsWith('ogg')) return '.ogg';
    return '.mp3';
  }

  static String _bingSsml(String text, AiTtsProviderSettings settings) {
    final language = settings.language.isEmpty ? 'zh-CN' : settings.language;
    final voice = settings.voice.isEmpty
        ? 'zh-CN-XiaoxiaoNeural'
        : settings.voice;
    final rate = settings.speed > 10
        ? '${(settings.speed - 100).round().clamp(-50, 100)}%'
        : '${((settings.speed - 1) * 100).round().clamp(-50, 100)}%';
    final pitch = settings.pitch > 10
        ? '${(settings.pitch - 50).round().clamp(-50, 50)}%'
        : '${((settings.pitch - 1) * 100).round().clamp(-50, 50)}%';
    final volume = settings.volume <= 1
        ? '${(settings.volume * 100).round().clamp(0, 100)}%'
        : '${settings.volume.round().clamp(0, 100)}%';
    return '''
<speak version="1.0" xml:lang="${escapeXmlAttribute(language)}">
  <voice xml:lang="${escapeXmlAttribute(language)}" name="${escapeXmlAttribute(voice)}">
    <prosody rate="$rate" pitch="$pitch" volume="$volume">${escapeXmlAttribute(text)}</prosody>
  </voice>
</speak>''';
  }

  static String _youdaoSignInput(String text) {
    if (text.length <= 20) return text;
    final headEnd = safeUtf16PrefixCodeUnits(text, 10);
    final tailStart = safeUtf16SuffixStart(text, text.length - 10);
    return '${text.substring(0, headEnd)}${text.length}${text.substring(tailStart)}';
  }

  static String _shortBody(http.Response response) {
    final body = collapseInlineWhitespace(response.body);
    return clipText(body, 180);
  }

  static String _playbackFailureMessage(Object error) {
    final raw = switch (error) {
      StateError() => error.message,
      HttpException() => error.message,
      ProcessException() => error.message,
      TimeoutException() => error.message ?? 'TTS 操作超时。',
      _ => error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), ''),
    };
    final normalized = collapseInlineWhitespace(raw);
    return clipText(normalized.isEmpty ? 'TTS 播放失败。' : normalized, 400);
  }

  static String _appleScriptString(String value) {
    return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }

  static String _extraString(
    AiTtsProviderSettings settings,
    String key, {
    String fallback = '',
  }) {
    final value = settings.extra[key];
    if (value is String) return nullIfBlank(value) ?? fallback;
    if (value is num || value is bool) return '$value';
    return fallback;
  }

  static int _extraInt(
    AiTtsProviderSettings settings,
    String key, {
    required int fallback,
  }) {
    final value = settings.extra[key];
    return optionalRoundedIntFromValue(value) ?? fallback;
  }

  static bool _extraBool(AiTtsProviderSettings settings, String key) {
    return optionalBoolFromValue(settings.extra[key]) ?? false;
  }

  static String _windowsSpeechScript(
    String text,
    AiTtsProviderSettings settings,
  ) {
    final escaped = text.replaceAll("'", "''");
    final volume =
        (settings.volume <= 1 ? settings.volume * 100 : settings.volume)
            .round()
            .clamp(0, 100);
    final rate = settings.speed > 10
        ? ((settings.speed - 50) / 5).round().clamp(-10, 10)
        : ((settings.speed - 1) * 5).round().clamp(-10, 10);
    return "Add-Type -AssemblyName System.Speech; "
        "\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
        "\$s.Volume = $volume; \$s.Rate = $rate; "
        "\$s.Speak('$escaped'); \$s.Dispose();";
  }
}

class _DoubaoJsonObjectParser {
  _DoubaoJsonObjectParser({
    required this.maxObjectChars,
    required this.onObject,
  });

  final int maxObjectChars;
  final void Function(String payload) onObject;
  final StringBuffer _current = StringBuffer();
  int _depth = 0;
  bool _inString = false;
  bool _escaped = false;

  void add(String chunk) {
    for (var index = 0; index < chunk.length; index++) {
      final code = chunk.codeUnitAt(index);
      if (_depth == 0) {
        if (code != 0x7b) continue;
        _current.writeCharCode(code);
        _depth = 1;
        _inString = false;
        _escaped = false;
        continue;
      }

      _current.writeCharCode(code);
      if (_current.length > maxObjectChars) {
        throw FormatException('豆包 TTS 事件超过 $maxObjectChars 个字符上限。');
      }
      if (_inString) {
        if (_escaped) {
          _escaped = false;
        } else if (code == 0x5c) {
          _escaped = true;
        } else if (code == 0x22) {
          _inString = false;
        }
        continue;
      }
      if (code == 0x22) {
        _inString = true;
      } else if (code == 0x7b) {
        _depth += 1;
      } else if (code == 0x7d) {
        _depth -= 1;
        if (_depth == 0) {
          final payload = _current.toString();
          _current.clear();
          onObject(payload);
        }
      }
    }
  }

  void finish() {
    if (_depth != 0 || _current.isNotEmpty) {
      throw const FormatException('豆包 TTS 返回了不完整 JSON。');
    }
  }
}

class _AiTtsOperation implements BoundedFileHandleOwner {
  _AiTtsOperation({required Duration timeout, required this.transport})
    : _deadline = MonotonicDeadline(timeout, timeoutMessage: 'TTS 合成超过总时限。');

  final AiTransportClient transport;
  final MonotonicDeadline _deadline;
  final Set<Process> _processes = <Process>{};
  final Map<Process, Future<void>> _processTerminations =
      <Process, Future<void>>{};
  final Set<WebSocket> _webSockets = <WebSocket>{};
  final Map<WebSocket, Future<void>> _webSocketCloses =
      <WebSocket, Future<void>>{};
  final Set<HttpClient> _httpClients = <HttpClient>{};
  final Set<RandomAccessFile> _files = <RandomAccessFile>{};
  final Map<RandomAccessFile, Future<void>> _fileCloses =
      <RandomAccessFile, Future<void>>{};
  final Set<Future<void>> _pendingAcquisitions = <Future<void>>{};
  final Set<Future<void>> _activeActivities = <Future<void>>{};
  final Completer<void> _cancelCompleter = Completer<void>();
  bool _cancelled = false;
  Future<void>? _closeFuture;

  bool get isCancelled => _cancelled;
  Duration get timeout => _deadline.timeout;
  Future<void> get cancelSignal => _cancelCompleter.future;

  void throwIfCancelled() {
    if (_cancelled) throw const _AiTtsPlaybackCancelled();
  }

  Duration remainingSynthesisTime() {
    throwIfCancelled();
    return _deadline.remaining();
  }

  void registerHttpClient(HttpClient client) {
    if (_cancelled) {
      client.close(force: true);
      throw const _AiTtsPlaybackCancelled();
    }
    _httpClients.add(client);
  }

  void releaseHttpClient(HttpClient client) {
    if (_httpClients.remove(client)) client.close(force: true);
  }

  Future<WebSocket> acquireWebSocket(
    Future<WebSocket> acquisition, {
    required Duration timeout,
    required VoidCallback onTimeout,
  }) {
    final guarded = () async {
      final socket = await acquisition.timeout(
        timeout,
        onTimeout: () {
          onTimeout();
          unawaited(
            acquisition.then<void>(
              AiTtsPlaybackService._closeWebSocketBounded,
              onError: (Object _, StackTrace _) {},
            ),
          );
          throw TimeoutException('TTS WebSocket 握手超时。', timeout);
        },
      );
      if (_cancelled) {
        await AiTtsPlaybackService._closeWebSocketBounded(socket);
        throw const _AiTtsPlaybackCancelled();
      }
      _webSockets.add(socket);
      return socket;
    }();
    _trackAcquisition(guarded);
    return guarded;
  }

  Future<void> releaseWebSocket(WebSocket socket) async {
    if (_webSockets.remove(socket)) {
      await _closeTrackedWebSocket(socket);
      return;
    }
    await (_webSocketCloses[socket] ?? Future<void>.value());
  }

  @override
  Future<RandomAccessFile> acquireFile(
    Future<RandomAccessFile> acquisition, {
    required Duration timeout,
    File? deleteIfAcquisitionCompletesLate,
  }) {
    final guarded = () async {
      final file = await acquisition.timeout(
        timeout,
        onTimeout: () {
          unawaited(
            acquisition.then<void>(
              (file) => _closeFileSilently(
                file,
                deleteAfterClose: deleteIfAcquisitionCompletesLate,
              ),
              onError: (Object _, StackTrace _) {},
            ),
          );
          throw TimeoutException('TTS 文件打开超时。', timeout);
        },
      );
      if (_cancelled) {
        await _closeFileSilently(
          file,
          deleteAfterClose: deleteIfAcquisitionCompletesLate,
        );
        throw const _AiTtsPlaybackCancelled();
      }
      _files.add(file);
      return file;
    }();
    _trackAcquisition(guarded);
    return guarded;
  }

  @override
  Future<void> releaseFile(RandomAccessFile file) async {
    if (_files.remove(file)) {
      await _closeTrackedFile(file);
      return;
    }
    await (_fileCloses[file] ?? Future<void>.value());
  }

  void releaseFileSynchronously(RandomAccessFile file) {
    if (!_files.contains(file)) return;
    file.closeSync();
    _files.remove(file);
  }

  Future<T> runTrackedActivity<T>(Future<T> Function() activity) async {
    throwIfCancelled();
    final completion = Completer<void>();
    final tracked = completion.future;
    _activeActivities.add(tracked);
    try {
      return await activity();
    } finally {
      if (!completion.isCompleted) completion.complete();
      _activeActivities.remove(tracked);
    }
  }

  Future<Process> acquireProcess(Future<Process> acquisition) {
    final guarded = () async {
      final process = await acquisition;
      if (_cancelled) {
        await _terminateProcessOnce(process);
        throw const _AiTtsPlaybackCancelled();
      }
      _processes.add(process);
      return process;
    }();
    _trackAcquisition(guarded);
    return guarded;
  }

  void unregisterProcess(Process process) {
    _processes.remove(process);
  }

  Future<void> terminateProcess(Process process) async {
    _processes.remove(process);
    await _terminateProcessOnce(process);
  }

  void _trackAcquisition<T>(Future<T> acquisition) {
    late final Future<void> completion;
    completion = acquisition.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pendingAcquisitions.add(completion);
    unawaited(
      completion.whenComplete(() => _pendingAcquisitions.remove(completion)),
    );
  }

  Future<void> close() {
    if (!_cancelled) {
      _cancelled = true;
      _cancelCompleter.complete();
      _deadline.stop();
      transport.dispose();
      for (final client in _httpClients) {
        client.close(force: true);
      }
      _httpClients.clear();
    }
    return _closeFuture ??= _closeResources();
  }

  Future<void> _closeResources() async {
    final sockets = _webSockets.toList(growable: false);
    _webSockets.clear();
    final processes = _processes.toList(growable: false);
    _processes.clear();
    final resourceCloses =
        <Future<void>>{
            for (final socket in sockets) _closeTrackedWebSocket(socket),
            for (final process in processes) _terminateProcessOnce(process),
          }
          ..addAll(_webSocketCloses.values)
          ..addAll(_processTerminations.values);
    await Future.wait<void>(resourceCloses).timeout(
      AiTtsPlaybackService._resourceCloseTimeout,
      onTimeout: () => <void>[],
    );
    final pending = _pendingAcquisitions.toList(growable: false);
    if (pending.isNotEmpty) {
      await Future.wait<void>(pending).timeout(
        AiTtsPlaybackService._resourceCloseTimeout,
        onTimeout: () => <void>[],
      );
    }
    final activities = _activeActivities.toList(growable: false);
    if (activities.isNotEmpty) {
      await Future.wait<void>(activities).timeout(
        AiTtsPlaybackService._resourceCloseTimeout,
        onTimeout: () => <void>[],
      );
    }
    if (_activeActivities.isEmpty &&
        (_files.isNotEmpty || _fileCloses.isNotEmpty)) {
      final files = _files.toList(growable: false);
      _files.clear();
      await Future.wait<void>(<Future<void>>{
        for (final file in files) _closeTrackedFile(file),
        ..._fileCloses.values,
      }).timeout(
        AiTtsPlaybackService._resourceCloseTimeout,
        onTimeout: () => <void>[],
      );
    }
  }

  static Future<void> _closeFileSilently(
    RandomAccessFile file, {
    File? deleteAfterClose,
  }) async {
    var closed = false;
    final closeFuture = file
        .close()
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() => closed = true);
    try {
      await closeFuture.timeout(AiTtsPlaybackService._resourceCloseTimeout);
    } catch (_) {
      // 操作已进入停止流程，清理仍受时限约束。
    }
    if (deleteAfterClose == null) return;
    if (closed) {
      await AiTtsPlaybackService._deletePlaybackFileSilently(deleteAfterClose);
    } else {
      unawaited(
        closeFuture.then(
          (_) => AiTtsPlaybackService._deletePlaybackFileSilently(
            deleteAfterClose,
          ),
        ),
      );
    }
  }

  Future<void> _closeTrackedFile(RandomAccessFile file) {
    return _fileCloses.putIfAbsent(file, () {
      return file
          .close()
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(() => _fileCloses.remove(file));
    });
  }

  Future<void> _closeTrackedWebSocket(WebSocket socket) {
    return _webSocketCloses.putIfAbsent(socket, () {
      return AiTtsPlaybackService._closeWebSocketBounded(socket).whenComplete(
        () {
          _webSocketCloses.remove(socket);
        },
      );
    });
  }

  Future<void> _terminateProcessOnce(Process process) {
    return _processTerminations.putIfAbsent(process, () {
      return _terminateProcessSilently(process).whenComplete(() {
        _processTerminations.remove(process);
      });
    });
  }

  static Future<void> _terminateProcessSilently(Process process) async {
    try {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: AiTtsPlaybackService._speechProcessTerminateGrace,
      );
    } catch (_) {
      // 取消清理仅尽力执行，并受调用方时限约束。
    }
  }
}

class _AiTtsPlaybackCancelled implements Exception {
  const _AiTtsPlaybackCancelled();
}

class _AiTtsAudioPayload {
  _AiTtsAudioPayload(List<int> sourceBytes, {required String extension})
    : bytes = sourceBytes is Uint8List
          ? sourceBytes
          : Uint8List.fromList(sourceBytes),
      extension = _normalizeExtension(extension) {
    if (bytes.isEmpty) throw StateError('TTS 返回了空音频。');
    if (bytes.length > AiTtsPlaybackService._maxAudioResponseBytes) {
      throw StateError(
        'TTS 音频超过 ${formatByteSize(AiTtsPlaybackService._maxAudioResponseBytes)} 的安全上限。',
      );
    }
  }

  final Uint8List bytes;
  final String extension;

  int get byteLength => bytes.length;

  static String _normalizeExtension(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '.mp3';
    return trimmed.startsWith('.') ? trimmed : '.$trimmed';
  }
}
