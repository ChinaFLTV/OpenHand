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
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/lifecycle_cache.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../../../shared/util/xml_escape.dart';
import '../../model/ai_creation_mode.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_tts_provider_catalog.dart';
import '../../model/ai_tts_settings.dart';
import '../media/ai_image_generation_service.dart';

class AiTtsPlaybackSnapshot {
  const AiTtsPlaybackSnapshot({
    this.playing = false,
    this.messageId,
    this.provider,
  });

  final bool playing;
  final String? messageId;
  final AiTtsProvider? provider;
}

class AiTtsPlaybackService {
  AiTtsPlaybackService({AiImageGenerationService? mediaGenerationService})
    : _mediaGenerationService =
          mediaGenerationService ?? AiImageGenerationService(),
      _ownsMediaGenerationService = mediaGenerationService == null;

  static const String settingsTestMessageId = '__settings_tts_test__';
  static const String settingsTestText = '这是一段文本转语音测试。';
  static const int _doubaoTtsSuccessCode = 20000000;
  static const String _defaultAiTtsAudioFormat = 'mp3';
  static const int _defaultAiTtsSampleRate = 24000;
  static const int _defaultAiTtsBitRate = 128000;
  static const int _audioCacheMaxEntries = 48;
  static const int _audioCacheMaxBytes = 64 * 1024 * 1024;
  static const Duration _speechProcessPipeDrainTimeout = Duration(
    milliseconds: 300,
  );
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
  static final RegExp _htmlTagPattern = RegExp(r'<[^>]+>');
  static final LifecycleLruCache<_AiTtsAudioPayload> _audioCache =
      LifecycleLruCache<_AiTtsAudioPayload>(
        maxEntries: _audioCacheMaxEntries,
        maxCost: _audioCacheMaxBytes,
        costOf: (audio) => audio.byteLength,
      );

  final AiImageGenerationService _mediaGenerationService;
  final bool _ownsMediaGenerationService;
  final ValueNotifier<AiTtsPlaybackSnapshot> state =
      ValueNotifier<AiTtsPlaybackSnapshot>(const AiTtsPlaybackSnapshot());
  int _generation = 0;
  Process? _activeProcess;
  WebSocket? _activeWebSocket;
  http.Client? _activeClient;
  Future<Set<String>>? _macOsVoiceNamesFuture;

  bool isPlayingMessage(String messageId) {
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
    await stop();
    final normalized = settings.normalized();
    if (!normalized.enabled) return;
    final content = _normalizeText(text, normalized.maxTextCharacters);
    if (content.isEmpty) return;
    final generation = ++_generation;
    for (final provider in normalized.providerPriority) {
      if (generation != _generation) return;
      final providerSettings = normalized.provider(provider);
      if (!providerSettings.enabled) continue;
      state.value = AiTtsPlaybackSnapshot(
        playing: true,
        messageId: messageId,
        provider: provider,
      );
      try {
        await _speakWithProvider(
          providerSettings,
          content,
          timeout: Duration(seconds: normalized.timeoutSeconds),
          availableModels: availableModels,
          fallbackModel: fallbackModel,
          isCurrent: () => generation == _generation,
        );
        if (generation == _generation) await stop();
        return;
      } catch (error, stack) {
        if (error is _AiTtsPlaybackCancelled) return;
        if (generation != _generation) return;
        if (!_isTtsConfigurationError(error)) {
          silentLog('tts', 'provider ${provider.storageKey}', error, stack);
        }
        await _stopActiveResources(clearState: false);
      }
    }
    if (generation == _generation) {
      state.value = const AiTtsPlaybackSnapshot();
    }
  }

  Future<void> testProvider({
    required AiTtsSettings settings,
    required AiTtsProvider provider,
    String text = settingsTestText,
    List<AiModelConfig> availableModels = const <AiModelConfig>[],
    AiModelConfig? fallbackModel,
  }) async {
    await stop();
    final normalized = settings.normalized();
    final content = _normalizeText(text, normalized.maxTextCharacters);
    if (content.isEmpty) {
      throw StateError('TTS test text is empty.');
    }
    final providerSettings = normalized.provider(provider);
    final generation = ++_generation;
    state.value = AiTtsPlaybackSnapshot(
      playing: true,
      messageId: settingsTestMessageId,
      provider: provider,
    );
    try {
      await _speakWithProvider(
        providerSettings,
        content,
        timeout: Duration(seconds: normalized.timeoutSeconds),
        availableModels: availableModels,
        fallbackModel: fallbackModel,
        isCurrent: () => generation == _generation,
      );
    } on _AiTtsPlaybackCancelled {
      return;
    } finally {
      if (generation == _generation) {
        await _stopActiveResources(clearState: true);
      }
    }
  }

  Future<void> stop() async {
    _generation += 1;
    await _stopActiveResources(clearState: true);
  }

  Future<void> dispose() async {
    await stop();
    if (_ownsMediaGenerationService) {
      _mediaGenerationService.dispose();
    }
    state.dispose();
  }

  static bool supportsAudioGenerationModel(
    AiModelConfig config,
    String modelId,
  ) {
    final normalizedModelId = modelId.trim();
    if (normalizedModelId.isEmpty) return false;
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
    required Duration timeout,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
    if (!_isCacheableTtsProvider(provider.provider)) {
      await _speakWithSystem(
        provider,
        text,
        timeout: timeout,
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
      timeout: timeout,
      availableModels: availableModels,
      fallbackModel: fallbackModel,
    );
    var audio = _audioCache.get(cacheKey);
    if (audio == null) {
      audio = await _synthesizeWithProvider(
        provider,
        text,
        timeout: timeout,
        availableModels: availableModels,
        fallbackModel: fallbackModel,
      );
      _audioCache.put(cacheKey, audio);
    }
    if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
    await _playAudioBytes(
      audio.bytes,
      extension: audio.extension,
      volume: _playbackVolume(provider, aiModel: resolvedAiModel),
      provider: provider,
      requestTimeout: timeout,
      isCurrent: isCurrent,
    );
  }

  Future<_AiTtsAudioPayload> _synthesizeWithProvider(
    AiTtsProviderSettings provider,
    String text, {
    required Duration timeout,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
  }) {
    switch (provider.provider) {
      case AiTtsProvider.ai:
        return _synthesizeWithAiModel(
          provider,
          text,
          timeout: timeout,
          availableModels: availableModels,
          fallbackModel: fallbackModel,
        );
      case AiTtsProvider.system:
      case AiTtsProvider.apple:
        throw StateError('System TTS is not cacheable.');
      case AiTtsProvider.xfyun:
        return _synthesizeWithXfyun(provider, text, timeout: timeout);
      case AiTtsProvider.baidu:
        return _synthesizeWithBaidu(provider, text, timeout: timeout);
      case AiTtsProvider.doubao:
        return _synthesizeWithDoubao(provider, text, timeout: timeout);
      case AiTtsProvider.mimo:
        return _synthesizeWithMimo(provider, text, timeout: timeout);
      case AiTtsProvider.youdao:
        return _synthesizeWithYoudao(provider, text, timeout: timeout);
      case AiTtsProvider.bing:
        return _synthesizeWithBing(provider, text, timeout: timeout);
      case AiTtsProvider.google:
        return _synthesizeWithGoogle(provider, text, timeout: timeout);
    }
  }

  Future<_AiTtsAudioPayload> _synthesizeWithAiModel(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
  }) async {
    final model = _resolveAiModel(
      settings: settings,
      availableModels: availableModels,
      fallbackModel: fallbackModel,
    );
    if (model == null) {
      throw StateError('AI TTS model is empty.');
    }
    if (!supportsAudioGenerationModel(model, model.modelId)) {
      throw StateError('AI TTS model does not support audio generation.');
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
    final result = await _mediaGenerationService.generateAudio(
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
      ),
      timeout: timeout,
    );
    final audioReference = _firstMediaReference(result.markdown);
    if (audioReference.isEmpty) {
      throw StateError('AI TTS returned no playable audio.');
    }
    return _audioPayloadFromReference(
      audioReference,
      outputFormat: outputFormat,
      timeout: timeout,
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
    required Duration timeout,
  }) async {
    if (settings.apiKey.isEmpty) {
      throw StateError('Mimo TTS API key is empty.');
    }
    final endpoint = _endpointOrDefault(settings);
    final uri = Uri.parse(endpoint);
    final model = _extraString(settings, 'model', fallback: 'mimo-v2.5-tts');
    final audioFormat = _extraString(settings, 'format', fallback: 'wav');
    final audio = <String, Object?>{
      'format': audioFormat,
      if (_mimoUsesPresetVoice(model)) 'voice': settings.voice.trim(),
      if (_mimoUsesVoiceClone(model))
        'voice': await _mimoVoiceSampleDataUrl(settings, timeout: timeout),
      if (!_mimoUsesPresetVoice(model) &&
          _extraBool(settings, 'optimize_text_preview'))
        'optimize_text_preview': true,
    };
    if (_mimoUsesPresetVoice(model) &&
        (audio['voice'] as String?)?.isEmpty != false) {
      throw StateError('Mimo TTS voice is empty.');
    }
    final client = http.Client();
    _activeClient = client;
    try {
      final response = await client
          .post(
            uri,
            headers: <String, String>{
              HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
              HttpHeaders.acceptHeader: 'application/json',
              'api-key': settings.apiKey,
            },
            body: jsonEncode(<String, Object?>{
              'model': model,
              'messages': <Object?>[
                <String, Object?>{
                  'role': 'user',
                  'content': _mimoStylePrompt(settings),
                },
                <String, Object?>{'role': 'assistant', 'content': text},
              ],
              'audio': audio,
            }),
          )
          .timeout(timeout);
      if (isHttpFailureStatus(response.statusCode)) {
        throw HttpException(
          'Mimo TTS HTTP ${response.statusCode}: ${_shortBody(response)}',
          uri: uri,
        );
      }
      final audioBytes =
          await compute(_decodeMimoAudioPayload, <String, Object?>{
            'body': response.body,
            'format': audioFormat,
            'sample_rate': _extraInt(settings, 'sample_rate', fallback: 24000),
          });
      return _AiTtsAudioPayload(
        audioBytes,
        extension: _mimoAudioExtension(audioFormat),
      );
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  Future<String> _mimoVoiceSampleDataUrl(
    AiTtsProviderSettings settings, {
    required Duration timeout,
  }) async {
    final path = _extraString(settings, 'voice_sample_path');
    if (path.isEmpty) {
      throw StateError('Mimo TTS voice sample path is empty.');
    }
    final file = File(path);
    final exists = await file.exists().timeout(timeout);
    if (!exists) {
      throw StateError('Mimo TTS voice sample file does not exist.');
    }
    final stat = await file.stat().timeout(timeout);
    const maxVoiceSampleBytes = 10 * 1024 * 1024;
    if (stat.size <= 0) {
      throw StateError('Mimo TTS voice sample file is empty.');
    }
    if (stat.size > maxVoiceSampleBytes) {
      throw StateError('Mimo TTS voice sample file is larger than 10 MB.');
    }
    final mimeType = _mimoVoiceSampleMimeType(path);
    if (mimeType == null) {
      throw StateError('Mimo TTS voice sample format must be mp3 or wav.');
    }
    final bytes = await file.readAsBytes().timeout(timeout);
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  Future<_AiTtsAudioPayload> _synthesizeWithDoubao(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
  }) async {
    if (settings.apiKey.isEmpty) {
      throw StateError('Doubao TTS API key is empty.');
    }
    final speaker = settings.voice.trim();
    if (speaker.isEmpty) {
      throw StateError('Doubao TTS speaker is empty.');
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
    final request = http.Request('POST', uri)
      ..headers.addAll(<String, String>{
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.acceptHeader: 'application/json',
        'X-Api-Key': settings.apiKey,
        'X-Api-Resource-Id': resourceId,
        'X-Api-Request-Id': requestId,
        HttpHeaders.connectionHeader: 'keep-alive',
      })
      ..body = jsonEncode(<String, Object?>{
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
            'disable_emoji_filter': _extraBool(
              settings,
              'disable_emoji_filter',
            ),
            if (explicitLanguage != null) 'explicit_language': explicitLanguage,
          }),
          'post_process': <String, Object?>{
            'pitch': settings.pitch.round().clamp(-12, 12),
          },
        },
      });
    final client = http.Client();
    _activeClient = client;
    try {
      final streamed = await client.send(request).timeout(timeout);
      if (isHttpFailureStatus(streamed.statusCode)) {
        throw HttpException('Doubao TTS HTTP ${streamed.statusCode}', uri: uri);
      }
      final audioBytes = BytesBuilder(copy: false);
      final pending = StringBuffer();
      await for (final chunk in streamed.stream.timeout(timeout)) {
        final textChunk = utf8.decode(chunk, allowMalformed: true);
        pending.write(textChunk);
        _drainDoubaoJsonLines(
          pending,
          onAudio: (audio) => audioBytes.add(base64Decode(audio)),
        );
      }
      _drainDoubaoJsonLines(
        pending,
        flush: true,
        onAudio: (audio) => audioBytes.add(base64Decode(audio)),
      );
      return _AiTtsAudioPayload(
        audioBytes.takeBytes(),
        extension: _audioExtension(audioFormat),
      );
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  Future<void> _speakWithSystem(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
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
        await _runSpeechProcess('say', <String>[
          '-v',
          voice,
          '-r',
          '${_systemRate(settings.speed)}',
          text,
        ], timeout: playbackTimeout);
        return;
      }
      await _runSpeechProcess('osascript', <String>[
        '-e',
        _macOsSpeechScript(text, settings),
      ], timeout: playbackTimeout);
      return;
    }
    if (Platform.isWindows) {
      if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
      final script = _windowsSpeechScript(text, settings);
      await _runSpeechProcess('powershell', <String>[
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ], timeout: playbackTimeout);
      return;
    }
    if (Platform.isLinux) {
      if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
      await _runSpeechProcess('spd-say', <String>[
        '-r',
        '${_linuxRate(settings.speed)}',
        text,
      ], timeout: playbackTimeout);
      return;
    }
    throw UnsupportedError('System TTS is not available on this platform.');
  }

  Future<_AiTtsAudioPayload> _synthesizeWithXfyun(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
  }) async {
    if (settings.appId.isEmpty ||
        settings.apiKey.isEmpty ||
        settings.apiSecret.isEmpty) {
      throw StateError('Xfyun TTS credentials are incomplete.');
    }
    final endpoint = _endpointOrDefault(settings);
    final uri = _xfyunAuthorizedUri(Uri.parse(endpoint), settings);
    final ws = await WebSocket.connect('$uri').timeout(timeout);
    _activeWebSocket = ws;
    final audioBytes = BytesBuilder(copy: false);
    ws.add(
      jsonEncode(<String, Object?>{
        'common': <String, Object?>{'app_id': settings.appId},
        'business': <String, Object?>{
          'aue': '${settings.extra['aue'] ?? 'lame'}',
          'auf': '${settings.extra['auf'] ?? 'audio/L16;rate=16000'}',
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
    await for (final event in ws.timeout(timeout)) {
      if (event is! String) continue;
      final decoded = jsonDecode(event);
      if (decoded is! Map) continue;
      final code = decoded['code'];
      if (code is int && code != 0) {
        throw StateError('Xfyun TTS failed: ${decoded['message'] ?? code}');
      }
      final data = decoded['data'];
      if (data is Map) {
        final audio = data['audio'];
        if (audio is String && audio.isNotEmpty) {
          audioBytes.add(base64Decode(audio));
        }
        if (data['status'] == 2) break;
      }
    }
    try {
      await ws.close().timeout(const Duration(seconds: 1));
    } finally {
      if (identical(_activeWebSocket, ws)) _activeWebSocket = null;
    }
    return _AiTtsAudioPayload(
      audioBytes.takeBytes(),
      extension: '${settings.extra['aue'] ?? 'mp3'}' == 'raw' ? '.pcm' : '.mp3',
    );
  }

  Future<_AiTtsAudioPayload> _synthesizeWithBaidu(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
  }) async {
    final accessToken = settings.accessToken.isNotEmpty
        ? settings.accessToken
        : await _fetchBaiduAccessToken(settings, timeout: timeout);
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
    final client = http.Client();
    _activeClient = client;
    try {
      final response = await client.get(uri).timeout(timeout);
      if (isHttpFailureStatus(response.statusCode)) {
        throw HttpException('Baidu TTS HTTP ${response.statusCode}', uri: uri);
      }
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.startsWith('audio/')) {
        throw StateError('Baidu TTS returned non-audio response.');
      }
      return _AiTtsAudioPayload(response.bodyBytes, extension: '.mp3');
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  Future<_AiTtsAudioPayload> _synthesizeWithGoogle(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
  }) async {
    if (settings.apiKey.isEmpty) {
      throw StateError('Google TTS API key is empty.');
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
    final client = http.Client();
    _activeClient = client;
    try {
      final response = await client
          .post(
            uri,
            headers: const <String, String>{
              HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
              HttpHeaders.acceptHeader: 'application/json',
            },
            body: jsonEncode(<String, Object?>{
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
            }),
          )
          .timeout(timeout);
      if (isHttpFailureStatus(response.statusCode)) {
        throw HttpException(
          'Google TTS HTTP ${response.statusCode}: ${_shortBody(response)}',
          uri: uri,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['audioContent'] is! String) {
        throw StateError('Google TTS returned invalid audio payload.');
      }
      return _AiTtsAudioPayload(
        base64Decode(decoded['audioContent'] as String),
        extension: _googleAudioExtension(audioEncoding),
      );
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  Future<_AiTtsAudioPayload> _synthesizeWithBing(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
  }) async {
    if (settings.apiKey.isEmpty) {
      throw StateError('Bing TTS subscription key is empty.');
    }
    final region = nullIfBlank(settings.region);
    final configuredEndpoint = nullIfBlank(settings.endpoint);
    if (region == null && configuredEndpoint == null) {
      throw StateError('Bing TTS region is empty.');
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
    final client = http.Client();
    _activeClient = client;
    try {
      final response = await client
          .post(
            uri,
            headers: <String, String>{
              HttpHeaders.contentTypeHeader: 'application/ssml+xml',
              HttpHeaders.acceptHeader: 'audio/*',
              'Ocp-Apim-Subscription-Key': settings.apiKey,
              'X-Microsoft-OutputFormat': outputFormat,
              'User-Agent': 'OpenHand',
            },
            body: _bingSsml(text, settings),
          )
          .timeout(timeout);
      if (isHttpFailureStatus(response.statusCode)) {
        throw HttpException(
          'Bing TTS HTTP ${response.statusCode}: ${_shortBody(response)}',
          uri: uri,
        );
      }
      return _AiTtsAudioPayload(
        response.bodyBytes,
        extension: _bingAudioExtension(outputFormat),
      );
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  Future<_AiTtsAudioPayload> _synthesizeWithYoudao(
    AiTtsProviderSettings settings,
    String text, {
    required Duration timeout,
  }) async {
    if (settings.apiKey.isEmpty || settings.apiSecret.isEmpty) {
      throw StateError('Youdao TTS credentials are incomplete.');
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
    final client = http.Client();
    _activeClient = client;
    try {
      final response = await client
          .post(
            uri,
            headers: const <String, String>{
              HttpHeaders.contentTypeHeader:
                  'application/x-www-form-urlencoded; charset=utf-8',
            },
            body: <String, String>{
              'q': text,
              'langType': settings.language.isEmpty
                  ? 'zh-CHS'
                  : settings.language,
              'appKey': settings.apiKey,
              'salt': salt,
              'sign': sign,
              'signType': 'v3',
              'curtime': '$curtime',
              if (settings.voice.isNotEmpty) 'voice': settings.voice,
              'format': 'mp3',
            },
          )
          .timeout(timeout);
      if (isHttpFailureStatus(response.statusCode)) {
        throw HttpException(
          'Youdao TTS HTTP ${response.statusCode}: ${_shortBody(response)}',
          uri: uri,
        );
      }
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.startsWith('audio/')) {
        throw StateError('Youdao TTS returned non-audio response.');
      }
      return _AiTtsAudioPayload(response.bodyBytes, extension: '.mp3');
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  Future<void> _playAudioBytes(
    List<int> bytes, {
    required String extension,
    required double volume,
    required AiTtsProviderSettings provider,
    required Duration requestTimeout,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
    if (bytes.isEmpty) throw StateError('TTS returned empty audio.');
    if (!Platform.isMacOS) {
      throw UnsupportedError('Audio playback is only wired for macOS now.');
    }
    final dir = Directory(
      p.join(OpenHandPaths.defaultCacheDirectoryPath(), 'tts'),
    );
    await dir.create(recursive: true);
    final file = File(
      p.join(
        dir.path,
        'tts_${DateTime.now().microsecondsSinceEpoch}$extension',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    try {
      if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
      final playbackTimeout = await _playbackTimeoutForAudioFile(
        file,
        byteLength: bytes.length,
        extension: extension,
        provider: provider,
        requestTimeout: requestTimeout,
      );
      if (!isCurrent()) throw const _AiTtsPlaybackCancelled();
      await _playAudioFile(file.path, volume: volume, timeout: playbackTimeout);
    } finally {
      unawaited(file.delete().catchError((_) => file));
    }
  }

  Future<void> _playAudioFile(
    String path, {
    required double volume,
    required Duration timeout,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('Audio playback is only wired for macOS now.');
    }
    final file = File(path);
    if (!await file.exists().timeout(timeout)) {
      throw StateError('TTS audio file is missing.');
    }
    await _runSpeechProcess('afplay', <String>[
      '-v',
      '${_afplayVolume(volume)}',
      file.path,
    ], timeout: timeout);
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
      silentLog(
        'ai_tts_playback_service',
        'probe audio duration',
        error,
        stack,
      );
      return null;
    }
  }

  Future<_AiTtsAudioPayload> _audioPayloadFromReference(
    String reference, {
    required String outputFormat,
    required Duration timeout,
  }) async {
    final normalized = reference.trim();
    if (normalized.isEmpty) {
      throw StateError('TTS audio reference is empty.');
    }
    final uri = Uri.tryParse(normalized);
    if (uri != null && uri.hasScheme) {
      if (uri.scheme == 'file') {
        return _audioPayloadFromFile(
          uri.toFilePath(),
          outputFormat: outputFormat,
          timeout: timeout,
        );
      }
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return _remoteAudioPayload(
          uri,
          outputFormat: outputFormat,
          timeout: timeout,
        );
      }
      throw StateError('AI TTS returned unsupported audio reference.');
    }
    return _audioPayloadFromFile(
      normalized,
      outputFormat: outputFormat,
      timeout: timeout,
    );
  }

  Future<_AiTtsAudioPayload> _audioPayloadFromFile(
    String path, {
    required String outputFormat,
    required Duration timeout,
  }) async {
    final file = File(path);
    if (!await file.exists().timeout(timeout)) {
      throw StateError('TTS audio file is missing.');
    }
    return _AiTtsAudioPayload(
      await file.readAsBytes().timeout(timeout),
      extension: _audioExtensionFromPath(path, fallbackFormat: outputFormat),
    );
  }

  Future<_AiTtsAudioPayload> _remoteAudioPayload(
    Uri uri, {
    required String outputFormat,
    required Duration timeout,
  }) async {
    final client = http.Client();
    _activeClient = client;
    try {
      final response = await client
          .get(
            uri,
            headers: const <String, String>{
              HttpHeaders.acceptHeader: 'audio/*',
            },
          )
          .timeout(timeout);
      if (isHttpFailureStatus(response.statusCode)) {
        throw HttpException(
          'AI TTS audio download HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final contentType = _responseContentType(response.headers);
      if (!_isPlayableAudioContentType(contentType)) {
        throw StateError('AI TTS audio URL returned non-audio content.');
      }
      return _AiTtsAudioPayload(
        response.bodyBytes,
        extension: _audioExtensionFromUri(uri, fallbackFormat: outputFormat),
      );
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  Future<void> _runSpeechProcess(
    String executable,
    List<String> args, {
    required Duration timeout,
  }) async {
    final process = await startTrackedProcessInNewGroup(executable, args);
    _activeProcess = process;
    final stderrBuffer = StringBuffer();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen((chunk) {
          if (stderrBuffer.length < 1000) stderrBuffer.write(chunk);
        })
        .asFuture<void>()
        .catchError((_) {});
    final stdoutDone = process.stdout.drain<void>().catchError((_) {});
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      await _drainSpeechProcessStreams(stderrDone, stdoutDone);
      if (exitCode != 0) {
        if (!identical(_activeProcess, process)) {
          throw const _AiTtsPlaybackCancelled();
        }
        final stderrText = stderrBuffer.toString().trim();
        throw ProcessException(
          executable,
          const <String>[],
          stderrText.isEmpty
              ? 'TTS process exited with code $exitCode'
              : 'TTS process exited with code $exitCode: $stderrText',
          exitCode,
        );
      }
    } on TimeoutException {
      final cancelled = !identical(_activeProcess, process);
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: _speechProcessTerminateGrace,
      );
      await _drainSpeechProcessStreams(stderrDone, stdoutDone);
      if (cancelled) throw const _AiTtsPlaybackCancelled();
      throw TimeoutException('TTS process timed out.', timeout);
    } finally {
      if (identical(_activeProcess, process)) _activeProcess = null;
    }
  }

  static Future<void> _drainSpeechProcessStreams(
    Future<void> stderrDone,
    Future<void> stdoutDone,
  ) {
    return Future.wait<void>([
      stderrDone.timeout(_speechProcessPipeDrainTimeout, onTimeout: () {}),
      stdoutDone.timeout(_speechProcessPipeDrainTimeout, onTimeout: () {}),
    ]);
  }

  Future<void> _stopActiveResources({required bool clearState}) async {
    final process = _activeProcess;
    _activeProcess = null;
    if (process != null) {
      try {
        await terminateTrackedProcessTree(
          process,
          gracefulTimeout: _speechProcessTerminateGrace,
        );
      } catch (error, stack) {
        silentLog(
          'ai_tts_playback_service',
          'kill active process',
          error,
          stack,
        );
      }
    }
    final ws = _activeWebSocket;
    _activeWebSocket = null;
    if (ws != null) {
      try {
        await ws.close().timeout(const Duration(seconds: 1));
      } catch (error, stack) {
        silentLog(
          'ai_tts_playback_service',
          'close active websocket',
          error,
          stack,
        );
      }
    }
    final client = _activeClient;
    _activeClient = null;
    client?.close();
    if (clearState) {
      state.value = const AiTtsPlaybackSnapshot();
    }
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
    required Duration timeout,
  }) async {
    if (settings.apiKey.isEmpty || settings.apiSecret.isEmpty) {
      throw StateError('Baidu TTS API key or secret is empty.');
    }
    final uri = Uri.parse('https://aip.baidubce.com/oauth/2.0/token').replace(
      queryParameters: <String, String>{
        'grant_type': 'client_credentials',
        'client_id': settings.apiKey,
        'client_secret': settings.apiSecret,
      },
    );
    final client = http.Client();
    _activeClient = client;
    try {
      final response = await client.post(uri).timeout(timeout);
      if (isHttpFailureStatus(response.statusCode)) {
        throw HttpException(
          'Baidu token HTTP ${response.statusCode}: ${_shortBody(response)}',
          uri: uri,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['access_token'] is! String) {
        throw StateError('Baidu token response is invalid.');
      }
      return decoded['access_token'] as String;
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  Future<String> _resolveMacOsVoice(String configuredVoice) async {
    final normalized = _macOsVoiceAlias(configuredVoice.trim());
    if (normalized.isEmpty || !Platform.isMacOS) return '';
    final voices = await (_macOsVoiceNamesFuture ??= _loadMacOsVoiceNames());
    if (voices.contains(normalized)) return normalized;
    final lower = normalized.toLowerCase();
    for (final voice in voices) {
      if (voice.toLowerCase() == lower) return voice;
    }
    return '';
  }

  Future<Set<String>> _loadMacOsVoiceNames() async {
    try {
      final result = await runTrackedProcessOrFailed(
        'say',
        const <String>['-v', '?'],
        timeout: const Duration(seconds: 2),
        tag: 'ai_tts.load_voices',
      );
      if (result.exitCode != 0) return const <String>{};
      final output = '${result.stdout}';
      return trimmedNonEmptyStrings(
        output
            .split('\n')
            .map(
              (line) => line
                  .trimLeft()
                  .split(_macOsVoiceColumnSeparatorPattern)
                  .first,
            ),
      ).toSet();
    } catch (error, stack) {
      silentLog(
        'ai_tts_playback_service',
        'load macOS voice names',
        error,
        stack,
      );
      return const <String>{};
    }
  }

  static String _normalizeText(String text, int maxCharacters) {
    final trimmed = collapseInlineWhitespace(
      text
          .replaceAll(_markdownCodeBlockPattern, ' ')
          .replaceAll(_htmlTagPattern, ' '),
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

  static double _afplayVolume(double volume) {
    return _unitPlaybackVolume(volume);
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

  static void _drainDoubaoJsonLines(
    StringBuffer pending, {
    bool flush = false,
    required void Function(String audioBase64) onAudio,
  }) {
    final source = pending.toString();
    final payloads = <String>[];
    var start = -1;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < source.length; i++) {
      final code = source.codeUnitAt(i);
      if (start < 0) {
        if (code == 123) {
          start = i;
          depth = 1;
        }
        continue;
      }
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 92) {
          escaped = true;
        } else if (code == 34) {
          inString = false;
        }
        continue;
      }
      if (code == 34) {
        inString = true;
      } else if (code == 123) {
        depth += 1;
      } else if (code == 125) {
        depth -= 1;
        if (depth == 0) {
          payloads.add(source.substring(start, i + 1));
          start = -1;
        }
      }
    }

    final remaining = start >= 0 ? source.substring(start) : '';
    pending
      ..clear()
      ..write(remaining);
    for (final payload in payloads) {
      _handleDoubaoPayload(payload, onAudio: onAudio);
    }
    if (!flush) return;
    final tail = pending.toString().trim();
    if (tail.isEmpty) return;
    _handleDoubaoPayload(tail, onAudio: onAudio);
    pending.clear();
  }

  static void _handleDoubaoPayload(
    String payload, {
    required void Function(String audioBase64) onAudio,
  }) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return;
    final code = decoded['code'];
    if (code is int && code != 0 && code != _doubaoTtsSuccessCode) {
      throw StateError('Doubao TTS failed: ${decoded['message'] ?? code}');
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

  static Uint8List _decodeMimoAudioPayload(Map<String, Object?> input) {
    final body = input['body'];
    final format = '${input['format'] ?? 'wav'}';
    final sampleRate = input['sample_rate'] is int
        ? input['sample_rate'] as int
        : 24000;
    if (body is! String || nullIfBlank(body) == null) {
      throw StateError('Mimo TTS returned empty response.');
    }
    final decoded = jsonDecode(body);
    final bytes = base64Decode(
      _chatCompletionAudioData(decoded, providerName: 'Mimo TTS'),
    );
    if (_isPcm16Format(format)) {
      return _wavBytesFromPcm16(bytes, sampleRate: sampleRate);
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
    throw StateError('$providerName returned invalid audio payload.');
  }

  static String? _audioDataFromObject(Object? audio) {
    if (audio is String) return optionalStringFromValue(audio);
    if (audio is! Map) return null;
    final data = audio['data'] ?? audio['audio'] ?? audio['audio_data'];
    return optionalStringFromValue(data);
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
        contentType.startsWith('audio/') ||
        contentType == 'application/octet-stream';
  }

  static String _mimoAudioExtension(String format) {
    if (_isPcm16Format(format)) return '.wav';
    return _audioExtension(format);
  }

  static bool _mimoUsesPresetVoice(String model) {
    final normalized = nullIfBlank(model);
    return normalized == null || normalized == 'mimo-v2.5-tts';
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
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
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
    return '${text.substring(0, 10)}${text.length}${text.substring(text.length - 10)}';
  }

  static String _shortBody(http.Response response) {
    final body = collapseInlineWhitespace(response.body);
    return clipText(body, 180);
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

  static bool _isTtsConfigurationError(Object error) {
    if (error is! StateError) return false;
    final message = error.message;
    return message.contains('credentials are incomplete') ||
        message.contains('API key is empty') ||
        message.contains('subscription key is empty') ||
        message.contains('region is empty') ||
        message.contains('speaker is empty') ||
        message.contains('voice is empty') ||
        message.contains('voice sample') ||
        message.contains('API key or secret is empty') ||
        message.contains('AI TTS model');
  }
}

class _AiTtsPlaybackCancelled implements Exception {
  const _AiTtsPlaybackCancelled();
}

class _AiTtsAudioPayload {
  _AiTtsAudioPayload(List<int> sourceBytes, {required String extension})
    : bytes = Uint8List.fromList(sourceBytes),
      extension = _normalizeExtension(extension) {
    if (bytes.isEmpty) throw StateError('TTS returned empty audio.');
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
