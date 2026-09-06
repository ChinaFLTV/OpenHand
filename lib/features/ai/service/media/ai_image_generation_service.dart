import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../../app/support/silent_log.dart';
import '../../../../shared/net/http_error_message.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/exponential_backoff.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_creation_mode.dart';
import '../../model/ai_model_catalog.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../../model/ai_tts_provider_catalog.dart';
import '../chat/ai_protocol_adapter.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../operations/ai_operation_http.dart';
import '../operations/ai_stepfun_audio_policy.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import '../session_io/ai_token_usage_parser.dart';

enum _GeneratedMediaKind {
  image('image', 'Image'),
  video('video', 'Video'),
  audio('audio', 'Audio');

  const _GeneratedMediaKind(this.storageValue, this.displayName);

  final String storageValue;
  final String displayName;

  bool get isImage => this == _GeneratedMediaKind.image;
  bool get isVideo => this == _GeneratedMediaKind.video;
  bool get isAudio => this == _GeneratedMediaKind.audio;
}

const Duration _pollMinimumRequestBudget = Duration(seconds: 1);
const Duration _pollRequestTimeoutCap = Duration(seconds: 15);
const Duration _retryAfterDelayCap = Duration(seconds: 30);
const Duration _soraContentDownloadTimeoutCap = Duration(seconds: 30);
const Duration _remoteMediaDownloadTimeout = Duration(seconds: 60);
const int _mediaJsonResponseMaxBytes = 64 * kBytesPerMiB;
const int _imageResponseMaxBytes = 128 * kBytesPerMiB;
const int _audioResponseMaxBytes = 64 * kBytesPerMiB;
const int _videoDownloadMaxBytes = 2 * kBytesPerGiB;
const int _referenceImageMaxBytes = 32 * kBytesPerMiB;
const int _referenceImagesMaxTotalBytes = 64 * kBytesPerMiB;
const int _referenceImageMaxCount = 8;
const int _generatedMediaOutputLimit = 16;
const int _mediaPayloadTraversalDepthLimit = 32;
const int _mediaPayloadMapVisitLimit = 10000;
const Set<String> _miniMaxImageStyles = <String>{'漫画', '元气', '中世纪', '水彩'};
const Duration _referenceImageReadIdleTimeout = Duration(seconds: 15);
const Duration _referenceImageReadTotalTimeout = Duration(minutes: 1);
const int _pollWarmupAttemptLimit = 6;
const int _pollSteadyAttemptLimit = 16;
const int _pollWarmupDelayMs = 1500;
const int _pollSteadyDelayMs = 3000;
const int _pollMaxDelayMs = 5000;
const int _pollMinDelayMs = 250;
const int _pollJitterWindowMs = 400;
const int _pollJitterHalfWindowMs = _pollJitterWindowMs ~/ 2;
const int _transientPollMaxFailures = 4;
const Duration _transientPollBackoffBase = Duration(milliseconds: 1500);
const Duration _transientPollBackoffCap = Duration(milliseconds: 8000);
const int _miniMaxFileRetrieveAttempts = 2;
const int _miniMaxFileRetrieveRetryBaseMs = 750;
const int _xaiVideoMinDurationSeconds = 1;
const int _xaiVideoMaxDurationSeconds = 15;
const int _gmiMusicPromptMaxCharacters = 2000;
const String _gmiMusicRequestUrl =
    'https://console.gmicloud.ai/api/v1/ie/requestqueue/apikey/requests';
const String _gmiMusicInstrumentalLyrics = '[Inst]';
const Set<String> _gmiMusicFormats = <String>{'mp3', 'wav', 'pcm'};
const Set<int> _gmiMusicSampleRates = <int>{16000, 24000, 32000, 44100};
const Set<int> _gmiMusicBitrates = <int>{32000, 64000, 128000, 256000};

/// 多媒体生成结果；[markdown] 可直接写入会话，[attachments] 记录本地文件。
class AiMediaGenerationResult {
  const AiMediaGenerationResult({
    required this.markdown,
    required this.rawResponseBody,
    required this.requestUrl,
    required this.requestBody,
    required this.requestHeaders,
    required this.startedAt,
    required this.endedAt,
    this.usage,
  });

  final String markdown;
  final String rawResponseBody;
  final String requestUrl;
  final Map<String, Object?> requestBody;
  final Map<String, String> requestHeaders;
  final DateTime startedAt;
  final DateTime endedAt;
  final AiTokenUsage? usage;

  int get durationMs => endedAt.difference(startedAt).inMilliseconds;
}

class AiMediaGenerationException implements Exception {
  const AiMediaGenerationException(this.message, {this.rawResponseBody});
  final String message;
  final String? rawResponseBody;
  @override
  String toString() => message;
}

class AiMediaGenerationCancelledException implements Exception {
  const AiMediaGenerationCancelledException();
}

/// 按供应商路由图片、视频和音频生成请求。
///
/// 多媒体接口具有独立请求结构和响应流程，因此与 [AiProtocolAdapter] 隔离，
/// 避免供应商差异影响聊天链路。
class AiImageGenerationService {
  AiImageGenerationService({http.Client? client, AiEndpointRouter? router})
    : _transport = AiTransportClient(client: client),
      _router = router ?? const AiEndpointRouter();

  static final RegExp _pixelSizePattern = RegExp(r'^(\d{2,5})x(\d{2,5})$');
  static final RegExp _base64LikePattern = RegExp(r'^[A-Za-z0-9+/=\r\n]+$');

  final AiTransportClient _transport;
  final AiEndpointRouter _router;

  /// 判断协议是否支持 OpenAI 兼容图片生成接口；Gemini 由聊天端点单独处理。
  static bool supportsImageGeneration(AiProtocolType protocol) {
    switch (protocol) {
      case AiProtocolType.openai:
      case AiProtocolType.qwen:
      case AiProtocolType.kimi:
      case AiProtocolType.glm:
      case AiProtocolType.grok:
      case AiProtocolType.deepseek:
      case AiProtocolType.seed:
      case AiProtocolType.stepfun:
      case AiProtocolType.minimax:
      case AiProtocolType.longcat:
      case AiProtocolType.agnes:
      case AiProtocolType.joycode:
      case AiProtocolType.wenxin:
      case AiProtocolType.meta:
      case AiProtocolType.hunyuan:
      case AiProtocolType.vllm:
      case AiProtocolType.sglang:
      case AiProtocolType.ollama:
        return true;
      case AiProtocolType.gemini:
      case AiProtocolType.claude:
      case AiProtocolType.dots:
      case AiProtocolType.mimo:
        return false;
    }
  }

  static bool supportsVideoGeneration(AiProtocolType protocol) {
    switch (protocol) {
      case AiProtocolType.openai:
      case AiProtocolType.qwen:
      case AiProtocolType.glm:
      case AiProtocolType.seed:
      case AiProtocolType.minimax:
      case AiProtocolType.agnes:
        return true;
      // xAI 原生接口与旧版 grok2api 网关均支持视频生成。
      case AiProtocolType.grok:
        return true;
      // 混元使用 TC3-HMAC RPC，文心和阶跃也无公开兼容端点，需专用适配器。
      case AiProtocolType.hunyuan:
      case AiProtocolType.stepfun:
      case AiProtocolType.wenxin:
      case AiProtocolType.gemini:
      case AiProtocolType.claude:
      case AiProtocolType.dots:
      case AiProtocolType.deepseek:
      case AiProtocolType.kimi:
      case AiProtocolType.ollama:
      case AiProtocolType.vllm:
      case AiProtocolType.sglang:
      case AiProtocolType.longcat:
      case AiProtocolType.joycode:
      case AiProtocolType.meta:
      case AiProtocolType.mimo:
        return false;
    }
  }

  static bool supportsImageGenerationForModel(AiModelConfig model) {
    return _supportsGenerationCapabilityForModel(
      model,
      model.resolveOperationModelId(AiApiFamily.imageGeneration),
      AiModelCapability.imageGeneration,
      protocolSupported: supportsImageGeneration(model.protocolType),
    );
  }

  static bool supportsVideoGenerationForModel(AiModelConfig model) {
    return _supportsGenerationCapabilityForModel(
      model,
      model.resolveOperationModelId(AiApiFamily.videoGeneration),
      AiModelCapability.videoGeneration,
      protocolSupported: supportsVideoGeneration(model.protocolType),
    );
  }

  static bool supportsAudioGenerationForModel(AiModelConfig model) {
    final speechModelId = model.resolveOperationModelId(
      AiApiFamily.audioSpeech,
    );
    final speechProfile = model.profileFor(speechModelId);
    if (speechProfile.capabilities.isNotEmpty) {
      return speechProfile.capabilities.contains(
        AiModelCapability.audioGeneration,
      );
    }
    final speechCatalog = AiModelCatalog.lookup(
      speechModelId,
      model.protocolType,
    );
    if (speechCatalog != null &&
        speechCatalog.capabilities.contains(
          AiModelCapability.audioGeneration,
        )) {
      return true;
    }
    return _supportsGenerationCapabilityForModel(
      model,
      speechModelId,
      AiModelCapability.audioGeneration,
      protocolSupported: supportsAudioGeneration(model.protocolType),
    );
  }

  static bool _supportsGenerationCapabilityForModel(
    AiModelConfig model,
    String modelId,
    AiModelCapability capability, {
    required bool protocolSupported,
  }) {
    final profile = model.profileFor(modelId);
    if (profile.capabilities.isNotEmpty) {
      return profile.capabilities.contains(capability);
    }
    final catalog = AiModelCatalog.lookup(modelId, model.protocolType);
    if (catalog != null) {
      return catalog.capabilities.contains(capability);
    }
    return protocolSupported;
  }

  static bool supportsAudioGeneration(AiProtocolType protocol) {
    switch (protocol) {
      case AiProtocolType.openai:
      case AiProtocolType.qwen:
      case AiProtocolType.glm:
      case AiProtocolType.minimax:
      case AiProtocolType.stepfun:
        return true;
      // 文心、混元和豆包语音使用专用签名 RPC，需专用适配器。
      case AiProtocolType.seed:
      case AiProtocolType.wenxin:
      case AiProtocolType.hunyuan:
      case AiProtocolType.gemini:
      case AiProtocolType.claude:
      case AiProtocolType.dots:
      case AiProtocolType.deepseek:
      case AiProtocolType.kimi:
      case AiProtocolType.grok:
      case AiProtocolType.ollama:
      case AiProtocolType.vllm:
      case AiProtocolType.sglang:
      case AiProtocolType.longcat:
      case AiProtocolType.agnes:
      case AiProtocolType.joycode:
      case AiProtocolType.meta:
      case AiProtocolType.mimo:
        return false;
    }
  }

  /// 返回图片生成模型标识，由用户在服务商设置中配置。
  static String resolveImageModelId(AiModelConfig model, AiCreationMode mode) {
    return mode == AiCreationMode.image
        ? model.resolveOperationModelId(AiApiFamily.imageGeneration)
        : model.resolveOperationModelId(AiApiFamily.imageEdit);
  }

  static String resolveVideoModelId(AiModelConfig model) {
    return model.resolveOperationModelId(AiApiFamily.videoGeneration);
  }

  static String resolveAudioModelId(AiModelConfig model) {
    return model.resolveOperationModelId(AiApiFamily.audioSpeech);
  }

  /// 通过 OpenAI 兼容端点生成图片；传输或解码失败时抛出 [AiMediaGenerationException]。
  Future<AiMediaGenerationResult> generateImage({
    required AiModelConfig model,
    required String prompt,
    AiCreationOptions options = AiCreationOptions.empty,
    List<AiChatContentPart> referenceImages = const <AiChatContentPart>[],
    Duration timeout = const Duration(seconds: 120),
    Future<void>? cancelSignal,
  }) async {
    if (!supportsImageGenerationForModel(model)) {
      throw AiMediaGenerationException(
        'Image generation is not implemented for protocol '
        '${model.protocolType.storageValue}.',
      );
    }
    final trimmedPrompt = nullIfBlank(prompt);
    if (trimmedPrompt == null) {
      throw const AiMediaGenerationException(
        'Refusing to call the image endpoint with an empty prompt.',
      );
    }
    if (model.protocolType == AiProtocolType.minimax &&
        trimmedPrompt.length > 1500) {
      throw const AiMediaGenerationException(
        'MiniMax image prompts cannot exceed 1500 characters.',
      );
    }
    final imageModelId = resolveImageModelId(model, AiCreationMode.image);
    final useGrok2Api = _usesGrok2Api(model);
    const family = AiApiFamily.imageGeneration;
    final useStepFunImageToImage =
        model.protocolType == AiProtocolType.stepfun &&
        referenceImages.isNotEmpty;
    final endpoint = _resolveMediaEndpoint(
      model,
      _GeneratedMediaKind.image,
      model.protocolType,
      modelId: imageModelId,
      fallbackPath: useStepFunImageToImage ? 'v1/images/image2image' : null,
    );
    final uri = AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family);
    final headers = _buildHeaders(
      model,
      family: family,
      endpointHeaders: endpoint.headers,
    );
    final referenceImageDataUrls =
        (_usesAgnesMediaApi(model.protocolType, imageModelId) ||
            useStepFunImageToImage ||
            model.protocolType == AiProtocolType.minimax ||
            model.protocolType == AiProtocolType.seed)
        ? await _referenceImageDataUrls(
            referenceImages,
            _GeneratedMediaKind.image,
          )
        : const <String>[];
    final body = AiOperationHttp.mergeBodyExtras(
      model,
      family,
      _buildImageBody(
        modelId: imageModelId,
        prompt: trimmedPrompt,
        options: options,
        protocol: model.protocolType,
        useGrok2Api: useGrok2Api,
        referenceImageDataUrls: referenceImageDataUrls,
      ),
    );
    final startedAt = DateTime.now().toUtc();
    final http.Response response;
    try {
      response = await _transport.sendJson(
        uri: uri,
        method: 'POST',
        headers: headers,
        body: body,
        timeout: timeout,
        maxResponseBytes: _imageResponseMaxBytes,
        cancelSignal: cancelSignal,
      );
    } on http.RequestAbortedException {
      throw const AiMediaGenerationCancelledException();
    } on TimeoutException {
      throw AiMediaGenerationException(
        _MediaErrorMessages.timeout(_GeneratedMediaKind.image, timeout),
      );
    } on HandshakeException catch (error) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.handshake(_GeneratedMediaKind.image, error),
      );
    } on TlsException catch (error) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.tls(_GeneratedMediaKind.image, error),
      );
    } on SocketException catch (error) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.socket(_GeneratedMediaKind.image, error),
      );
    } on HttpException catch (error) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.response(_GeneratedMediaKind.image, error),
      );
    } on http.ClientException catch (error) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.httpClient(_GeneratedMediaKind.image, error),
      );
    }
    final endedAt = DateTime.now().toUtc();
    if (isHttpFailureStatus(response.statusCode)) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.httpStatus(
          _GeneratedMediaKind.image,
          response.statusCode,
          serverMessage: _extractError(response.body),
        ),
        rawResponseBody: response.body,
      );
    }
    final decoded = _decodeJson(response.body);
    _throwIfMiniMaxProviderFailed(
      decoded,
      kind: _GeneratedMediaKind.image,
      protocol: model.protocolType,
      rawResponseBody: response.body,
    );
    final markdown = await _buildMarkdownFromResponse(
      decoded: decoded,
      altText: trimmedPrompt,
      cancelSignal: cancelSignal,
    );
    if (markdown.isEmpty) {
      throw AiMediaGenerationException(
        'Image endpoint returned no recognisable image payload.',
        rawResponseBody: response.body,
      );
    }
    return AiMediaGenerationResult(
      markdown: markdown,
      rawResponseBody: response.body,
      requestUrl: uri.toString(),
      requestBody: body,
      requestHeaders: Map<String, String>.unmodifiable(headers),
      startedAt: startedAt,
      endedAt: endedAt,
      usage: AiTokenUsageParser.parseResponsePayload(decoded),
    );
  }

  Future<AiMediaGenerationResult> generateVideo({
    required AiModelConfig model,
    required String prompt,
    AiCreationOptions options = AiCreationOptions.empty,
    List<AiChatContentPart> referenceImages = const <AiChatContentPart>[],
    Duration timeout = const Duration(minutes: 15),
    Future<void>? cancelSignal,
  }) {
    return _generateMedia(
      kind: _GeneratedMediaKind.video,
      model: model,
      prompt: prompt,
      options: options,
      referenceImages: referenceImages,
      timeout: timeout,
      cancelSignal: cancelSignal,
    );
  }

  Future<AiMediaGenerationResult> generateAudio({
    required AiModelConfig model,
    required String prompt,
    AiCreationOptions options = AiCreationOptions.empty,
    Duration timeout = const Duration(minutes: 3),
    Future<void>? cancelSignal,
  }) {
    return _generateMedia(
      kind: _GeneratedMediaKind.audio,
      model: model,
      prompt: prompt,
      options: options,
      timeout: timeout,
      cancelSignal: cancelSignal,
    );
  }

  Future<AiMediaGenerationResult> _generateMedia({
    required _GeneratedMediaKind kind,
    required AiModelConfig model,
    required String prompt,
    required AiCreationOptions options,
    List<AiChatContentPart> referenceImages = const <AiChatContentPart>[],
    required Duration timeout,
    Future<void>? cancelSignal,
  }) async {
    final supported = switch (kind) {
      _GeneratedMediaKind.image => supportsImageGenerationForModel(model),
      _GeneratedMediaKind.video => supportsVideoGenerationForModel(model),
      _GeneratedMediaKind.audio => supportsAudioGenerationForModel(model),
    };
    if (!supported) {
      throw AiMediaGenerationException(
        '${kind.displayName} generation is not implemented for protocol '
        '${model.protocolType.storageValue}.',
      );
    }
    final trimmedPrompt = nullIfBlank(prompt);
    if (trimmedPrompt == null) {
      throw AiMediaGenerationException(
        'Refusing to call the ${kind.storageValue} endpoint with an empty prompt.',
      );
    }
    if (model.protocolType == AiProtocolType.minimax) {
      final maxCharacters = kind.isVideo ? 2000 : 9999;
      if (trimmedPrompt.length > maxCharacters) {
        throw AiMediaGenerationException(
          'MiniMax ${kind.storageValue} input cannot exceed '
          '$maxCharacters characters.',
        );
      }
    }
    final modelId = switch (kind) {
      _GeneratedMediaKind.image => resolveImageModelId(
        model,
        AiCreationMode.image,
      ),
      _GeneratedMediaKind.video => resolveVideoModelId(model),
      _GeneratedMediaKind.audio => resolveAudioModelId(model),
    };
    final useGmiMusicApi = kind.isAudio && _usesGmiMusicApi(model, modelId);
    if (useGmiMusicApi &&
        trimmedPrompt.runes.length > _gmiMusicPromptMaxCharacters) {
      throw const AiMediaGenerationException(
        'GMI MiniMax Music 风格描述不能超过 2000 个字符。',
      );
    }
    final useGrok2Api = _usesGrok2Api(model);
    final inputError = kind.isAudio
        ? AiStepFunAudioPolicy.inputValidationError(
            protocol: model.protocolType,
            modelId: modelId,
            input: trimmedPrompt,
          )
        : null;
    if (inputError != null) {
      throw AiMediaGenerationException(inputError);
    }
    final family = _familyForKind(kind);
    final endpoint = _resolveMediaEndpoint(
      model,
      kind,
      model.protocolType,
      modelId: modelId,
    );
    final uri = AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family);
    final headers = _buildHeaders(
      model,
      family: family,
      endpointHeaders: endpoint.headers,
    );
    if (!model.customHeaders.keys.any(
      (key) => lowercaseStringFromValue(key) == kAcceptHeaderName,
    )) {
      headers[kAcceptHeaderName] = _acceptHeaderFor(kind);
    }
    // 通义视频任务必须携带异步请求头，且不覆盖用户自定义值。
    if (kind.isVideo && model.protocolType == AiProtocolType.qwen) {
      final hasOverride = model.customHeaders.keys.any(
        (key) => lowercaseStringFromValue(key) == 'x-dashscope-async',
      );
      if (!hasOverride) {
        headers['x-dashscope-async'] = 'enable';
      }
    }
    final referenceImageDataUrls =
        (_usesAgnesMediaApi(model.protocolType, modelId) ||
            model.protocolType == AiProtocolType.minimax ||
            model.protocolType == AiProtocolType.seed ||
            (model.protocolType == AiProtocolType.grok && !useGrok2Api))
        ? await _referenceImageDataUrls(referenceImages, kind)
        : const <String>[];
    final body = AiOperationHttp.mergeBodyExtras(
      model,
      family,
      _buildMediaBody(
        kind: kind,
        modelId: modelId,
        prompt: trimmedPrompt,
        options: options,
        protocol: model.protocolType,
        useGrok2Api: useGrok2Api,
        useGmiMusicApi: useGmiMusicApi,
        referenceImageDataUrls: referenceImageDataUrls,
      ),
    );
    final useMultipart = _videoEndpointWantsMultipart(
      kind: kind,
      protocol: model.protocolType,
      modelId: modelId,
      useGrok2Api: useGrok2Api,
    );
    final startedAt = DateTime.now().toUtc();
    final operationStopwatch = Stopwatch()..start();
    final http.Response response;
    try {
      if (useMultipart) {
        // OpenAI Sora 2 与旧版 grok2api 要求 multipart/form-data。
        response = await _transport.sendMultipart(
          uri: uri,
          method: 'POST',
          headers: headers,
          body: body,
          timeout: timeout,
          maxResponseBytes: _maxResponseBytesFor(kind),
          cancelSignal: cancelSignal,
        );
      } else {
        response = await _transport.sendJson(
          uri: uri,
          method: 'POST',
          headers: headers,
          body: body,
          timeout: timeout,
          maxResponseBytes: _maxResponseBytesFor(kind),
          cancelSignal: cancelSignal,
        );
      }
    } on http.RequestAbortedException {
      throw const AiMediaGenerationCancelledException();
    } on TimeoutException {
      throw AiMediaGenerationException(
        _MediaErrorMessages.timeout(kind, timeout),
      );
    } on HandshakeException catch (error) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.handshake(kind, error),
      );
    } on TlsException catch (error) {
      throw AiMediaGenerationException(_MediaErrorMessages.tls(kind, error));
    } on SocketException catch (error) {
      throw AiMediaGenerationException(_MediaErrorMessages.socket(kind, error));
    } on HttpException catch (error) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.response(kind, error),
      );
    } on http.ClientException catch (error) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.httpClient(kind, error),
      );
    }
    final endedAt = DateTime.now().toUtc();
    if (isHttpFailureStatus(response.statusCode)) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.httpStatus(
          kind,
          response.statusCode,
          serverMessage: _extractError(response.body),
        ),
        rawResponseBody: response.body,
      );
    }

    final contentType = responseMimeType(response.headers);
    if (_isBinaryMediaContentType(contentType, kind)) {
      final markdown = await _saveBinaryMediaBytes(
        kind: kind,
        bytes: response.bodyBytes,
        mimeType: contentType,
        label: trimmedPrompt,
      );
      if (markdown.isEmpty) {
        throw AiMediaGenerationException(
          '${kind.displayName} endpoint returned an empty binary payload.',
          rawResponseBody: response.body,
        );
      }
      return AiMediaGenerationResult(
        markdown: markdown,
        rawResponseBody: response.body,
        requestUrl: uri.toString(),
        requestBody: body,
        requestHeaders: Map<String, String>.unmodifiable(headers),
        startedAt: startedAt,
        endedAt: endedAt,
      );
    }

    final decoded = _decodeJsonForKind(response.body, kind);
    final initialUsage = AiTokenUsageParser.parseResponsePayload(decoded);
    _throwIfMiniMaxProviderFailed(
      decoded,
      kind: kind,
      protocol: model.protocolType,
      rawResponseBody: response.body,
    );
    final initialStatus = _operationStatus(decoded);
    if (_isTerminalFailureStatus(initialStatus)) {
      throw AiMediaGenerationException(
        '${kind.displayName} generation failed: ${_extractError(response.body)}',
        rawResponseBody: response.body,
      );
    }
    final initialMarkdown = await _buildMarkdownFromMediaResponse(
      decoded: decoded,
      kind: kind,
      label: trimmedPrompt,
      cancelSignal: cancelSignal,
    );
    if (initialMarkdown.isNotEmpty) {
      return AiMediaGenerationResult(
        markdown: initialMarkdown,
        rawResponseBody: response.body,
        requestUrl: uri.toString(),
        requestBody: body,
        requestHeaders: Map<String, String>.unmodifiable(headers),
        startedAt: startedAt,
        endedAt: endedAt,
        usage: initialUsage,
      );
    }

    final pollingTimeout = timeout - operationStopwatch.elapsed;
    if (pollingTimeout <= Duration.zero) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.timeout(kind, timeout),
      );
    }
    final polled = await _pollMediaOperation(
      initialUrl: uri.toString(),
      initialPayload: decoded,
      kind: kind,
      label: trimmedPrompt,
      protocol: model.protocolType,
      modelId: modelId,
      requestHeaders: headers,
      timeout: pollingTimeout,
      cancelSignal: cancelSignal,
      initialUsage: initialUsage,
    );
    if (polled.markdown.isEmpty) {
      throw AiMediaGenerationException(
        '${kind.displayName} endpoint returned no recognisable media payload.',
        rawResponseBody: response.body,
      );
    }
    return AiMediaGenerationResult(
      markdown: polled.markdown,
      rawResponseBody: polled.rawResponseBody,
      requestUrl: uri.toString(),
      requestBody: body,
      requestHeaders: Map<String, String>.unmodifiable(headers),
      startedAt: startedAt,
      endedAt: DateTime.now().toUtc(),
      usage: polled.usage,
    );
  }

  AiApiFamily _familyForKind(_GeneratedMediaKind kind) {
    return switch (kind) {
      _GeneratedMediaKind.image => AiApiFamily.imageGeneration,
      _GeneratedMediaKind.video => AiApiFamily.videoGeneration,
      _GeneratedMediaKind.audio => AiApiFamily.audioSpeech,
    };
  }

  int _maxResponseBytesFor(_GeneratedMediaKind kind) {
    return switch (kind) {
      _GeneratedMediaKind.image => _imageResponseMaxBytes,
      _GeneratedMediaKind.video => _mediaJsonResponseMaxBytes,
      _GeneratedMediaKind.audio => _audioResponseMaxBytes,
    };
  }

  AiResolvedEndpoint _resolveMediaEndpoint(
    AiModelConfig model,
    _GeneratedMediaKind kind,
    AiProtocolType protocol, {
    required String modelId,
    String? fallbackPath,
  }) {
    if (nullIfBlank(model.normalizedBaseUrl) == null) {
      throw const AiMediaGenerationException('Missing base URL.');
    }
    if (kind.isAudio && _usesGmiMusicApi(model, modelId)) {
      return const AiResolvedEndpoint(
        url: _gmiMusicRequestUrl,
        method: 'POST',
        transport: 'json',
      );
    }
    final family = _familyForKind(kind);
    return _router.resolve(
      model,
      family,
      method: model.requestMethod,
      fallbackPath:
          fallbackPath ?? _fallbackMediaPath(model, kind, protocol, modelId),
    );
  }

  String _fallbackMediaPath(
    AiModelConfig model,
    _GeneratedMediaKind kind,
    AiProtocolType protocol,
    String modelId,
  ) {
    if (protocol == AiProtocolType.seed) {
      return kind.isVideo
          ? 'api/v3/contents/generations/tasks'
          : kind.isImage
          ? 'api/v3/images/generations'
          : 'v1/${_mediaEndpointSuffix(kind, protocol, modelId).join('/')}';
    }
    if (protocol == AiProtocolType.grok &&
        kind.isVideo &&
        !_usesGrok2Api(model)) {
      return 'v1/videos/generations';
    }
    return 'v1/${_mediaEndpointSuffix(kind, protocol, modelId).join('/')}';
  }

  List<String> _mediaEndpointSuffix(
    _GeneratedMediaKind kind,
    AiProtocolType protocol,
    String modelId,
  ) {
    if (kind.isVideo) {
      return switch (protocol) {
        // OpenAI Sora 2 使用 `/v1/videos` 异步任务接口。
        AiProtocolType.openai => const <String>['videos'],
        // 旧版 grok2api 网关沿用 OpenAI Sora 的 `/v1/videos` 异步格式。
        AiProtocolType.grok => const <String>['videos'],
        AiProtocolType.agnes => const <String>['videos'],
        // MiniMax 使用扁平的 `/v1/video_generation` 路径。
        AiProtocolType.minimax => const <String>['video_generation'],
        // GLM 和通义兼容模式使用各自的视频生成路径。
        _ =>
          _isAgnesModel(modelId)
              ? const <String>['videos']
              : const <String>['videos', 'generations'],
      };
    }
    if (kind.isAudio) {
      return switch (protocol) {
        // MiniMax T2A v2 端点。
        AiProtocolType.minimax when _isMiniMaxMusicModel(modelId) =>
          const <String>['music_generation'],
        AiProtocolType.minimax => const <String>['t2a_v2'],
        _ => const <String>['audio', 'speech'],
      };
    }
    return switch (protocol) {
      AiProtocolType.minimax => const <String>['image_generation'],
      _ => const <String>['images', 'generations'],
    };
  }

  Map<String, String> _buildHeaders(
    AiModelConfig model, {
    required AiApiFamily family,
    required Map<String, String> endpointHeaders,
  }) {
    return AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpointHeaders,
      family: family,
      acceptJson: true,
    );
  }

  String _acceptHeaderFor(_GeneratedMediaKind kind) {
    return switch (kind) {
      _GeneratedMediaKind.image => kApplicationJsonMimeType,
      _GeneratedMediaKind.video => 'application/json, video/*;q=0.9',
      _GeneratedMediaKind.audio => 'application/json, audio/*;q=0.9',
    };
  }

  /// 判断目标视频端点是否要求 `multipart/form-data`。
  bool _videoEndpointWantsMultipart({
    required _GeneratedMediaKind kind,
    required AiProtocolType protocol,
    required String modelId,
    required bool useGrok2Api,
  }) {
    if (!kind.isVideo) return false;
    // Agnes 视频端点仅接受 JSON，multipart 会错误地字符串化数值字段。
    if (_usesAgnesMediaApi(protocol, modelId)) return false;
    // OpenAI Sora 2 与旧版 grok2api 使用 multipart/form-data。
    return protocol == AiProtocolType.openai || useGrok2Api;
  }

  Map<String, Object?> _buildMediaBody({
    required _GeneratedMediaKind kind,
    required String modelId,
    required String prompt,
    required AiCreationOptions options,
    required AiProtocolType protocol,
    required bool useGrok2Api,
    required bool useGmiMusicApi,
    required List<String> referenceImageDataUrls,
  }) {
    return switch (kind) {
      _GeneratedMediaKind.image => _buildImageBody(
        modelId: modelId,
        prompt: prompt,
        options: options,
        protocol: protocol,
        useGrok2Api: useGrok2Api,
        referenceImageDataUrls: referenceImageDataUrls,
      ),
      _GeneratedMediaKind.video => _buildVideoBody(
        modelId: modelId,
        prompt: prompt,
        options: options,
        protocol: protocol,
        useGrok2Api: useGrok2Api,
        referenceImageDataUrls: referenceImageDataUrls,
      ),
      _GeneratedMediaKind.audio => _buildAudioBody(
        modelId: modelId,
        prompt: prompt,
        options: options,
        protocol: protocol,
        useGmiMusicApi: useGmiMusicApi,
      ),
    };
  }

  void _putBool(Map<String, Object?> body, String key, bool? value) {
    if (value == null) return;
    body[key] = value;
  }

  void _putPositiveInt(Map<String, Object?> body, String key, int? value) {
    if (value == null || value <= 0) return;
    body[key] = value;
  }

  void _putPositiveDouble(
    Map<String, Object?> body,
    String key,
    double? value,
  ) {
    if (value == null || value <= 0 || value.isNaN || value.isInfinite) {
      return;
    }
    body[key] = value;
  }

  Map<String, Object?> _buildImageBody({
    required String modelId,
    required String prompt,
    required AiCreationOptions options,
    required AiProtocolType protocol,
    required bool useGrok2Api,
    required List<String> referenceImageDataUrls,
  }) {
    if (_usesAgnesMediaApi(protocol, modelId)) {
      final body = <String, Object?>{
        'model': modelId,
        'prompt': prompt,
        'size':
            options.size ??
            _agnesImageSizeFromAspectRatio(options.aspectRatio) ??
            '1024x1024',
      };
      if (referenceImageDataUrls.isEmpty) {
        body['return_base64'] = true;
      } else {
        body['extra_body'] = <String, Object?>{
          'image': referenceImageDataUrls,
          'response_format': 'b64_json',
        };
      }
      return body;
    }
    if (protocol == AiProtocolType.grok && !useGrok2Api) {
      final body = <String, Object?>{
        'model': modelId,
        'prompt': prompt,
        'n': options.count.clamp(1, AiCreationOptions.maxCount),
      };
      putIfNotBlank(body, 'aspect_ratio', options.aspectRatio);
      final resolution = optionalLowercaseStringFromValue(options.resolution);
      if (resolution == '1k' || resolution == '2k') {
        body['resolution'] = resolution;
      }
      final quality = optionalLowercaseStringFromValue(options.quality);
      if (quality == 'low' || quality == 'medium') {
        body['quality'] = quality;
      }
      return body;
    }
    if (protocol == AiProtocolType.seed) {
      final body = <String, Object?>{
        'model': modelId,
        'prompt': prompt,
        'response_format': 'b64_json',
      };
      if (referenceImageDataUrls.length == 1) {
        body['image'] = referenceImageDataUrls.first;
      } else if (referenceImageDataUrls.isNotEmpty) {
        body['image'] = referenceImageDataUrls;
      }
      putIfNotBlank(body, 'size', options.size ?? options.resolution);
      putIfNotBlank(body, 'output_format', options.outputFormat);
      _putBool(body, 'watermark', options.watermark);
      if (options.count > 1 && !_isSeedream5Pro(modelId)) {
        body['sequential_image_generation'] = 'auto';
        body['sequential_image_generation_options'] = <String, Object?>{
          'max_images': options.count.clamp(1, AiCreationOptions.maxCount),
        };
      }
      return body;
    }
    if (protocol == AiProtocolType.minimax) {
      final requestedFormat = optionalLowercaseStringFromValue(
        options.outputFormat,
      );
      final responseFormat =
          requestedFormat == 'base64' || requestedFormat == 'b64_json'
          ? 'base64'
          : 'url';
      final body = <String, Object?>{
        'model': modelId,
        'prompt': prompt,
        'response_format': responseFormat,
        'n': options.count.clamp(1, 9),
        if (options.promptEnhance != null)
          'prompt_optimizer': options.promptEnhance,
        if (options.watermark != null) 'aigc_watermark': options.watermark,
        if (options.seed != null) 'seed': options.seed,
      };
      final aspectRatio = nullIfBlank(options.aspectRatio);
      if (aspectRatio != null) {
        body['aspect_ratio'] = aspectRatio;
      } else {
        final size = _parsePixelSize(options.size);
        if (size != null &&
            size.width >= 512 &&
            size.width <= 2048 &&
            size.height >= 512 &&
            size.height <= 2048 &&
            size.width % 8 == 0 &&
            size.height % 8 == 0) {
          body['width'] = size.width;
          body['height'] = size.height;
        }
      }
      final style = nullIfBlank(options.style);
      if (modelId.toLowerCase() == 'image-01-live' &&
          style != null &&
          _miniMaxImageStyles.contains(style)) {
        body['style'] = <String, Object?>{
          'style_type': style,
          'style_weight': 0.8,
        };
      }
      if (referenceImageDataUrls.isNotEmpty) {
        body['subject_reference'] = referenceImageDataUrls
            .map(
              (image) => <String, Object?>{
                'type': 'character',
                'image_file': image,
              },
            )
            .toList(growable: false);
      }
      return body;
    }
    final body = <String, Object?>{
      'model': modelId,
      'prompt': prompt,
      'n': protocol == AiProtocolType.stepfun
          ? 1
          : (options.count > 0 ? options.count : 1),
      'response_format': 'b64_json',
    };
    // 将宽高比转换为部分服务商要求的具体尺寸。
    final size = options.size ?? _sizeFromAspectRatio(options.aspectRatio);
    if (size != null) body['size'] = size;
    if (options.aspectRatio != null) {
      // 通义、Grok 和豆包接受 aspect_ratio。
      body['aspect_ratio'] = options.aspectRatio;
    }
    if (options.quality != null) body['quality'] = options.quality;
    if (options.style != null) body['style'] = options.style;
    if (protocol == AiProtocolType.stepfun) {
      if (referenceImageDataUrls.isNotEmpty) {
        body['source_url'] = referenceImageDataUrls.first;
        body['source_weight'] = _sourceWeightFromOptions(options);
      }
      _putPositiveInt(body, 'seed', options.seed);
      _putPositiveInt(body, 'steps', _stepsFromQuality(options.quality));
      _putPositiveDouble(body, 'cfg_scale', _doubleFromStyle(options.style));
      putIfNotBlank(body, 'negative_prompt', options.negativePrompt);
      _putBool(body, 'text_mode', options.promptEnhance);
      body.remove('aspect_ratio');
      body.remove('quality');
      body.remove('style');
    } else if (protocol == AiProtocolType.openai) {
      final lowerModel = lowercaseStringFromValue(modelId);
      if (lowerModel.startsWith('gpt-image')) {
        putIfNotBlank(body, 'output_format', options.outputFormat);
        putIfNotBlank(body, 'background', options.background);
      }
    } else {
      putIfNotBlank(body, 'output_format', options.outputFormat);
      putIfNotBlank(body, 'background', options.background);
      putIfNotBlank(body, 'negative_prompt', options.negativePrompt);
      _putPositiveInt(body, 'seed', options.seed);
      _putBool(body, 'prompt_extend', options.promptEnhance);
      _putBool(body, 'prompt_optimizer', options.promptEnhance);
      _putBool(body, 'watermark', options.watermark);
    }
    return body;
  }

  Map<String, Object?> _buildVideoBody({
    required String modelId,
    required String prompt,
    required AiCreationOptions options,
    required AiProtocolType protocol,
    required bool useGrok2Api,
    required List<String> referenceImageDataUrls,
  }) {
    if (_usesAgnesMediaApi(protocol, modelId)) {
      return _buildAgnesVideoBody(
        modelId: modelId,
        prompt: prompt,
        options: options,
        referenceImageDataUrls: referenceImageDataUrls,
      );
    }
    // 各厂商媒体请求结构不同，必须按原生协议构造，避免服务端拒绝未知字段。
    switch (protocol) {
      case AiProtocolType.openai:
        // Sora 2 不接受数量字段。
        final body = <String, Object?>{'model': modelId, 'prompt': prompt};
        final size = _videoSizeFromOptions(options);
        if (size != null) body['size'] = size;
        if (options.durationSeconds != null) {
          body['seconds'] = options.durationSeconds;
        }
        return body;
      case AiProtocolType.minimax:
        final normalizedModelId = lowercaseStringFromValue(modelId);
        final subjectReference = normalizedModelId.startsWith('s2v-');
        final body = <String, Object?>{
          'model': modelId,
          'prompt': prompt,
          'prompt_optimizer': options.promptEnhance ?? true,
          if (options.watermark != null) 'aigc_watermark': options.watermark,
        };
        if (subjectReference && referenceImageDataUrls.isNotEmpty) {
          body['subject_reference'] = <Map<String, Object?>>[
            <String, Object?>{
              'type': 'character',
              'image': <String>[referenceImageDataUrls.first],
            },
          ];
          return body;
        }
        if (referenceImageDataUrls.isNotEmpty) {
          body['first_frame_image'] = referenceImageDataUrls.first;
        }
        if (referenceImageDataUrls.length > 1) {
          body['last_frame_image'] = referenceImageDataUrls[1];
        }
        if (options.durationSeconds != null) {
          body['duration'] = options.durationSeconds;
        }
        final resolution = nullIfBlank(options.resolution);
        if (resolution != null) body['resolution'] = resolution.toUpperCase();
        return body;
      case AiProtocolType.qwen:
        // 通义使用原生的 input/parameters 请求结构。
        final parameters = <String, Object?>{};
        final size = _videoSizeFromOptions(options);
        if (size != null) parameters['size'] = size;
        if (options.durationSeconds != null) {
          parameters['duration'] = options.durationSeconds;
        }
        putIfNotBlank(parameters, 'negative_prompt', options.negativePrompt);
        _putPositiveInt(parameters, 'seed', options.seed);
        _putBool(parameters, 'prompt_extend', options.promptEnhance);
        _putBool(parameters, 'watermark', options.watermark);
        return <String, Object?>{
          'model': modelId,
          'input': <String, Object?>{'prompt': prompt},
          if (parameters.isNotEmpty) 'parameters': parameters,
        };
      case AiProtocolType.grok:
        if (!useGrok2Api) {
          final body = <String, Object?>{'model': modelId, 'prompt': prompt};
          final duration = options.durationSeconds;
          if (duration != null) {
            body['duration'] = duration.clamp(
              _xaiVideoMinDurationSeconds,
              _xaiVideoMaxDurationSeconds,
            );
          }
          putIfNotBlank(body, 'aspect_ratio', options.aspectRatio);
          putIfNotBlank(body, 'resolution', options.resolution);
          if (referenceImageDataUrls.isNotEmpty) {
            body['image_url'] = referenceImageDataUrls.first;
          }
          return body;
        }
        // 旧版 grok2api：`POST /v1/videos`，使用 multipart 请求。
        final body = <String, Object?>{'model': modelId, 'prompt': prompt};
        final size = _videoSizeFromOptions(options);
        if (size != null) body['size'] = size;
        if (options.durationSeconds != null) {
          body['seconds'] = options.durationSeconds;
        }
        // grok2api 通过 quality/style 映射分辨率和预设。
        final resolutionName =
            nullIfBlank(options.resolution) ?? options.quality;
        putIfNotBlank(body, 'resolution_name', resolutionName);
        if (options.style != null) {
          body['preset'] = options.style;
        }
        return body;
      case AiProtocolType.agnes:
        return _buildAgnesVideoBody(
          modelId: modelId,
          prompt: prompt,
          options: options,
          referenceImageDataUrls: referenceImageDataUrls,
        );
      case AiProtocolType.glm:
      case AiProtocolType.hunyuan:
      case AiProtocolType.stepfun:
      case AiProtocolType.wenxin:
      case AiProtocolType.gemini:
      case AiProtocolType.claude:
      case AiProtocolType.dots:
      case AiProtocolType.deepseek:
      case AiProtocolType.kimi:
      case AiProtocolType.ollama:
      case AiProtocolType.vllm:
      case AiProtocolType.sglang:
      case AiProtocolType.longcat:
      case AiProtocolType.joycode:
      case AiProtocolType.meta:
      case AiProtocolType.mimo:
        // GLM CogVideoX 及兼容网关使用扁平视频参数。
        final body = <String, Object?>{
          'model': modelId,
          'prompt': prompt,
          'response_format': 'url',
        };
        if (options.aspectRatio != null) {
          body['aspect_ratio'] = options.aspectRatio;
        }
        final size = _videoSizeFromOptions(options);
        if (size != null) body['size'] = size;
        if (options.durationSeconds != null) {
          body['duration'] = options.durationSeconds;
          body['duration_seconds'] = options.durationSeconds;
        }
        if (options.quality != null) body['quality'] = options.quality;
        if (options.style != null) body['style'] = options.style;
        putIfNotBlank(body, 'negative_prompt', options.negativePrompt);
        _putPositiveInt(body, 'seed', options.seed);
        _putBool(body, 'prompt_extend', options.promptEnhance);
        _putBool(body, 'prompt_optimizer', options.promptEnhance);
        _putBool(body, 'watermark', options.watermark);
        putIfNotBlank(body, 'resolution', options.resolution);
        _putPositiveInt(body, 'frame_rate', options.frameRate);
        _putPositiveInt(body, 'fps', options.frameRate);
        _putPositiveInt(body, 'num_frames', options.numFrames);
        putIfNotBlank(body, 'mode', options.mode);
        return body;
      case AiProtocolType.seed:
        final content = <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': prompt},
        ];
        if (referenceImageDataUrls.length <= 2) {
          for (var i = 0; i < referenceImageDataUrls.length; i++) {
            content.add(<String, Object?>{
              'type': 'image_url',
              'image_url': <String, Object?>{'url': referenceImageDataUrls[i]},
              'role': i == 0 ? 'first_frame' : 'last_frame',
            });
          }
        } else {
          for (final imageUrl in referenceImageDataUrls) {
            content.add(<String, Object?>{
              'type': 'image_url',
              'image_url': <String, Object?>{'url': imageUrl},
              'role': 'reference_image',
            });
          }
        }
        final body = <String, Object?>{'model': modelId, 'content': content};
        putIfNotBlank(body, 'resolution', options.resolution);
        putIfNotBlank(body, 'ratio', options.aspectRatio);
        _putPositiveInt(body, 'duration', options.durationSeconds);
        _putPositiveInt(body, 'seed', options.seed);
        _putBool(body, 'watermark', options.watermark);
        return body;
    }
  }

  /// 将宽高比映射为仅接受绝对分辨率的服务商所需尺寸。
  String? _videoSizeFromOptions(AiCreationOptions options) {
    return nullIfBlank(options.size) ??
        _videoSizeFromAspectRatio(
          options.aspectRatio,
          resolution: options.resolution,
        );
  }

  String? _videoSizeFromAspectRatio(String? ratio, {String? resolution}) {
    final normalizedRatio = nullIfBlank(ratio);
    if (normalizedRatio == null) return null;
    final preset = optionalLowercaseStringFromValue(resolution);
    if (preset == null || preset == '720p') {
      switch (normalizedRatio) {
        case '1:1':
          return '1024x1024';
        case '16:9':
          return '1280x720';
        case '9:16':
          return '720x1280';
        case '4:3':
          return '1024x768';
        case '3:4':
          return '768x1024';
      }
      return null;
    }
    final height = switch (preset) {
      '480p' => 480,
      '1080p' => 1080,
      _ => 720,
    };
    switch (normalizedRatio) {
      case '1:1':
        final side = height == 480 ? 512 : (height == 1080 ? 1536 : 1024);
        return '${side}x$side';
      case '16:9':
        final width = ((height * 16 / 9) / 2).round() * 2;
        return '${width}x$height';
      case '9:16':
        final width = height;
        final portraitHeight = ((height * 16 / 9) / 2).round() * 2;
        return '${width}x$portraitHeight';
      case '4:3':
        final width = ((height * 4 / 3) / 2).round() * 2;
        return '${width}x$height';
      case '3:4':
        final width = height;
        final portraitHeight = ((height * 4 / 3) / 2).round() * 2;
        return '${width}x$portraitHeight';
    }
    return null;
  }

  String? _agnesImageSizeFromAspectRatio(String? ratio) {
    final normalizedRatio = nullIfBlank(ratio);
    if (normalizedRatio == null) return null;
    switch (normalizedRatio) {
      case '1:1':
        return '1024x1024';
      case '16:9':
        return '1024x576';
      case '9:16':
        return '576x1024';
      case '4:3':
        return '1024x768';
      case '3:4':
        return '768x1024';
      case '3:2':
        return '1152x768';
      case '2:3':
        return '768x1152';
    }
    return null;
  }

  Map<String, Object?> _buildAgnesVideoBody({
    required String modelId,
    required String prompt,
    required AiCreationOptions options,
    required List<String> referenceImageDataUrls,
  }) {
    final frameRate = _agnesFrameRate(options.frameRate);
    final size =
        _parsePixelSize(options.size) ??
        _agnesVideoSizeFromAspectRatio(
          options.aspectRatio,
          resolution: options.resolution,
        );
    final body = <String, Object?>{
      'model': modelId,
      'prompt': prompt,
      'height': size.height,
      'width': size.width,
      'num_frames': _agnesNumFrames(
        durationSeconds: options.durationSeconds,
        frameRate: frameRate,
        explicitFrames: options.numFrames,
      ),
      'frame_rate': frameRate,
    };
    putIfNotBlank(body, 'negative_prompt', options.negativePrompt);
    _putPositiveInt(body, 'seed', options.seed);
    if (referenceImageDataUrls.length == 1) {
      body['image'] = referenceImageDataUrls.first;
    } else if (referenceImageDataUrls.length > 1) {
      body['extra_body'] = <String, Object?>{
        'image': referenceImageDataUrls,
        'mode': 'keyframes',
      };
    }
    return body;
  }

  int _agnesFrameRate(int? value) {
    if (value == null || value <= 0) return 24;
    return value.clamp(1, 60);
  }

  _PixelSize _agnesVideoSizeFromAspectRatio(
    String? ratio, {
    String? resolution,
  }) {
    final preset = optionalLowercaseStringFromValue(resolution);
    _PixelSize scale(int width720, int height720) {
      final multiplier = switch (preset) {
        '480p' => 2 / 3,
        '1080p' => 1.5,
        _ => 1.0,
      };
      final width = ((width720 * multiplier) / 8).round() * 8;
      final height = ((height720 * multiplier) / 8).round() * 8;
      return _PixelSize(width: math.max(8, width), height: math.max(8, height));
    }

    switch (nullIfBlank(ratio)) {
      case '1:1':
        return scale(1024, 1024);
      case '16:9':
        return scale(1280, 720);
      case '9:16':
        return scale(720, 1280);
      case '4:3':
        return scale(1024, 768);
      case '3:4':
        return scale(768, 1024);
      case '1.5:1':
      case '3:2':
      default:
        return scale(1152, 768);
    }
  }

  int _agnesNumFrames({
    required int? durationSeconds,
    required int frameRate,
    required int? explicitFrames,
  }) {
    final rawTarget = explicitFrames != null && explicitFrames > 0
        ? explicitFrames
        : (durationSeconds == null || durationSeconds <= 0
              ? 121
              : durationSeconds * frameRate);
    final target = math.min(441, math.max(9, rawTarget));
    final steps = ((target - 1) / 8).round();
    return math.min(441, math.max(9, steps * 8 + 1));
  }

  _PixelSize? _parsePixelSize(String? raw) {
    final trimmed = nullIfBlank(raw);
    if (trimmed == null) return null;
    final match = _pixelSizePattern.firstMatch(trimmed);
    if (match == null) return null;
    final width = optionalPositiveIntFromValue(match.group(1));
    final height = optionalPositiveIntFromValue(match.group(2));
    if (width == null || height == null) return null;
    return _PixelSize(width: width, height: height);
  }

  Future<List<String>> _referenceImageDataUrls(
    List<AiChatContentPart> referenceImages,
    _GeneratedMediaKind kind,
  ) async {
    if (!kind.isImage && !kind.isVideo) return const <String>[];
    final dataUrls = <String>[];
    var totalBytes = 0;
    for (final part in referenceImages) {
      if (part.kind != AiChatContentPartKind.imageFile) continue;
      if (dataUrls.length >= _referenceImageMaxCount) {
        throw const AiMediaGenerationException(
          'Reference image count exceeds the $_referenceImageMaxCount image limit.',
        );
      }
      final filePath = nullIfBlank(part.filePath);
      if (filePath == null) continue;
      final mimeType = nullIfBlank(part.mimeType) ?? _mimeFromUrl(filePath);
      final bytes = await _readReferenceImageBytes(filePath, kind);
      if (bytes.isEmpty) {
        throw AiMediaGenerationException(
          'Reference image "$filePath" is empty.',
        );
      }
      if (totalBytes > _referenceImagesMaxTotalBytes - bytes.length) {
        throw AiMediaGenerationException(
          'Reference images exceed the ${formatByteSize(_referenceImagesMaxTotalBytes)} total limit.',
        );
      }
      totalBytes += bytes.length;
      dataUrls.add('data:$mimeType;base64,${base64Encode(bytes)}');
    }
    return dataUrls.toList(growable: false);
  }

  Future<List<int>> _readReferenceImageBytes(
    String filePath,
    _GeneratedMediaKind kind,
  ) async {
    final file = File(filePath);
    try {
      return await readBoundedFileBytes(
        file,
        maxBytes: _referenceImageMaxBytes,
        idleTimeout: _referenceImageReadIdleTimeout,
        totalTimeout: _referenceImageReadTotalTimeout,
      );
    } on AiMediaGenerationException {
      rethrow;
    } on BoundedFileReadException catch (error) {
      final detail = error.failure == BoundedFileReadFailure.tooLarge
          ? 'exceeds the ${formatByteSize(_referenceImageMaxBytes)} per-file limit'
          : 'changed while it was being read';
      throw AiMediaGenerationException('Reference image $detail.');
    } on TimeoutException {
      throw AiMediaGenerationException(
        'Reference image read timed out for ${kind.storageValue} generation.',
      );
    } on FileSystemException catch (error) {
      throw AiMediaGenerationException(
        'Unable to read reference image for ${kind.storageValue} generation: '
        '${error.message}',
      );
    }
  }

  bool _usesAgnesMediaApi(AiProtocolType protocol, String modelId) {
    return protocol == AiProtocolType.agnes || _isAgnesModel(modelId);
  }

  static bool _isAgnesModel(String modelId) {
    return lowercaseStringFromValue(modelId).startsWith('agnes-');
  }

  bool _usesGrok2Api(AiModelConfig model) {
    if (model.protocolType != AiProtocolType.grok) return false;
    final videoModelId = lowercaseStringFromValue(
      model.resolveOperationModelId(AiApiFamily.videoGeneration),
    );
    if (videoModelId == 'grok-imagine-video' || videoModelId == 'grok-video') {
      return true;
    }
    final override = model.endpointOverrides[AiApiFamily.videoGeneration];
    for (final value in <String?>[
      model.normalizedBaseUrl,
      override?.url,
      override?.path,
    ]) {
      final normalized = optionalLowercaseStringFromValue(value);
      if (normalized == null) continue;
      if (normalized.contains('grok2api')) return true;
      final uri = Uri.tryParse(normalized);
      final segments = uri?.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
      if (segments != null &&
          segments.isNotEmpty &&
          segments.last == 'videos') {
        return true;
      }
    }
    return false;
  }

  static bool _isSeedream5Pro(String modelId) {
    return lowercaseStringFromValue(
      modelId,
    ).startsWith('doubao-seedream-5-0-pro');
  }

  static bool _isMiniMaxMusicModel(String modelId) {
    return lowercaseStringFromValue(modelId).contains('music');
  }

  static bool _usesGmiMusicApi(AiModelConfig model, String modelId) {
    if (!_isMiniMaxMusicModel(modelId)) return false;
    final host =
        Uri.tryParse(model.normalizedBaseUrl)?.host.toLowerCase() ?? '';
    return host == 'api.gmi-serving.com' ||
        host.endsWith('.gmi-serving.com') ||
        host == 'gmicloud.ai' ||
        host.endsWith('.gmicloud.ai');
  }

  Map<String, Object?> _buildAudioBody({
    required String modelId,
    required String prompt,
    required AiCreationOptions options,
    required AiProtocolType protocol,
    required bool useGmiMusicApi,
  }) {
    final voice = options.omitVoice
        ? null
        : nullIfBlank(options.voice) ?? nullIfBlank(options.style);
    final format = nullIfBlank(options.outputFormat) ?? 'mp3';
    if (useGmiMusicApi) {
      final payload = <String, Object?>{
        'lyrics': _gmiMusicInstrumentalLyrics,
        'prompt': prompt,
      };
      if (_gmiMusicSampleRates.contains(options.sampleRate)) {
        payload['sample_rate'] = options.sampleRate;
      }
      if (_gmiMusicBitrates.contains(options.bitrate)) {
        payload['bitrate'] = options.bitrate;
      }
      payload['format'] = _gmiMusicFormats.contains(format) ? format : 'mp3';
      return <String, Object?>{'model': modelId, 'payload': payload};
    }
    switch (protocol) {
      case AiProtocolType.openai:
      case AiProtocolType.glm:
      case AiProtocolType.stepfun:
        // OpenAI TTS 与 GLM CogTTS 共用标准语音请求结构。
        final body = <String, Object?>{
          'model': modelId,
          'input': prompt,
          if (!options.omitVoice)
            'voice':
                voice ??
                _defaultVoiceForAudioProtocol(
                  protocol: protocol,
                  modelId: modelId,
                ),
          'response_format': format,
        };
        _putPositiveDouble(body, 'speed', options.speed);
        if (AiStepFunAudioPolicy.isStepFunSpeech(
          protocol: protocol,
          modelId: modelId,
        )) {
          _putPositiveDouble(body, 'volume', options.volume);
          _putPositiveInt(body, 'sample_rate', options.sampleRate);
          final normalized = AiStepFunAudioPolicy.normalizeSpeechBody(
            body: body,
            protocol: protocol,
            modelId: modelId,
          );
          if (options.omitVoice) normalized.remove('voice');
          return normalized;
        }
        return body;
      case AiProtocolType.qwen:
        // 通义 Qwen3-TTS/cosyvoice 使用原生 input/parameters 结构。
        final parameters = <String, Object?>{
          if (voice != null) 'voice': voice,
          'format': format,
        };
        _putPositiveDouble(parameters, 'speed', options.speed);
        _putPositiveInt(parameters, 'sample_rate', options.sampleRate);
        return <String, Object?>{
          'model': modelId,
          'input': <String, Object?>{'text': prompt},
          'parameters': parameters,
        };
      case AiProtocolType.minimax:
        if (_isMiniMaxMusicModel(modelId)) {
          return <String, Object?>{
            'model': modelId,
            'prompt': prompt,
            'stream': false,
            'output_format': 'url',
            'is_instrumental': true,
            'audio_setting': <String, Object?>{
              'sample_rate': options.sampleRate ?? 44100,
              'bitrate': options.bitrate ?? 256000,
              'format': format == 'pcm' ? 'wav' : format,
            },
            if (options.watermark != null) 'aigc_watermark': options.watermark,
          };
        }
        // MiniMax T2A v2 分别使用音色与音频设置。
        return <String, Object?>{
          'model': modelId,
          'text': prompt,
          'voice_setting': <String, Object?>{
            if (!options.omitVoice)
              'voice_id': options.timbreWeights.isEmpty
                  ? voice ?? 'female-shaonv'
                  : '',
            'speed': options.speed ?? 1.0,
            'vol': options.volume ?? 1.0,
            'pitch': (options.pitch ?? 0).round(),
            if (nullIfBlank(options.emotion) != null)
              'emotion': options.emotion,
            if (options.textNormalization != null)
              'text_normalization': options.textNormalization,
            if (options.latexRead != null) 'latex_read': options.latexRead,
          },
          'audio_setting': <String, Object?>{
            'sample_rate': options.sampleRate ?? 32000,
            'bitrate': options.bitrate ?? 128000,
            'format': format,
            if (options.channel != null) 'channel': options.channel,
            if (options.forceCbr != null) 'force_cbr': options.forceCbr,
          },
          if (options.pronunciationTone.isNotEmpty)
            'pronunciation_dict': <String, Object?>{
              'tone': options.pronunciationTone,
            },
          if (options.timbreWeights.isNotEmpty)
            'timbre_weights': options.timbreWeights,
          if (nullIfBlank(options.languageBoost) != null)
            'language_boost': options.languageBoost,
          if (options.voiceModify.isNotEmpty)
            'voice_modify': options.voiceModify,
          if (options.subtitleEnable != null)
            'subtitle_enable': options.subtitleEnable,
          if (nullIfBlank(options.subtitleType) != null)
            'subtitle_type': options.subtitleType,
          // URL 输出避免在内存中保留大段十六进制响应，并交由受限下载器校验。
          'output_format': 'url',
          if (options.watermark != null) 'aigc_watermark': options.watermark,
        };
      case AiProtocolType.seed:
      case AiProtocolType.wenxin:
      case AiProtocolType.hunyuan:
      case AiProtocolType.gemini:
      case AiProtocolType.claude:
      case AiProtocolType.dots:
      case AiProtocolType.deepseek:
      case AiProtocolType.kimi:
      case AiProtocolType.grok:
      case AiProtocolType.ollama:
      case AiProtocolType.vllm:
      case AiProtocolType.sglang:
      case AiProtocolType.longcat:
      case AiProtocolType.agnes:
      case AiProtocolType.joycode:
      case AiProtocolType.meta:
      case AiProtocolType.mimo:
        // 自定义兼容网关使用通用 OpenAI 请求结构。
        final body = <String, Object?>{
          'model': modelId,
          'input': prompt,
          if (!options.omitVoice)
            'voice':
                voice ??
                _defaultVoiceForAudioProtocol(
                  protocol: protocol,
                  modelId: modelId,
                ),
          'response_format': format,
          if (options.speed != null) 'speed': options.speed,
          if (options.sampleRate != null) 'sample_rate': options.sampleRate,
          if (options.bitrate != null) 'bitrate': options.bitrate,
          if (options.volume != null) 'volume': options.volume,
          if (options.pitch != null) 'pitch': options.pitch,
        };
        final normalized = AiStepFunAudioPolicy.normalizeSpeechBody(
          body: body,
          protocol: protocol,
          modelId: modelId,
        );
        if (options.omitVoice) normalized.remove('voice');
        return normalized;
    }
  }

  String? _sizeFromAspectRatio(String? ratio) {
    final normalizedRatio = nullIfBlank(ratio);
    if (normalizedRatio == null) return null;
    switch (normalizedRatio) {
      case '1:1':
        return '1024x1024';
      case '16:9':
        return '1792x1024';
      case '9:16':
        return '1024x1792';
      case '4:3':
        return '1152x896';
      case '3:4':
        return '896x1152';
      case '3:2':
        return '1216x832';
      case '2:3':
        return '832x1216';
    }
    return null;
  }

  int? _stepsFromQuality(String? value) {
    return optionalPositiveIntFromValue(value);
  }

  double? _doubleFromStyle(String? value) {
    return optionalDoubleFromValue(value);
  }

  double _sourceWeightFromOptions(AiCreationOptions options) {
    final parsed = _doubleFromStyle(options.style);
    if (parsed == null || parsed <= 0) return 0.5;
    return parsed > 1 ? 1 : parsed;
  }

  String _defaultVoiceForAudioProtocol({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    return AiTtsProviderCatalogs.defaultVoiceForAiModel(
      protocol: protocol,
      modelId: modelId,
    );
  }

  Map<String, Object?> _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) return decoded;
    } catch (error, stack) {
      silentLog('ai_image_generation_service', '解码响应正文', error, stack);
    }
    throw AiMediaGenerationException(
      'Image endpoint returned a non-JSON response.',
      rawResponseBody: body,
    );
  }

  Map<String, Object?> _decodeJsonForKind(
    String body,
    _GeneratedMediaKind kind,
  ) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) return decoded;
    } catch (error, stack) {
      silentLog(
        'ai_image_generation_service',
        '解码 ${kind.storageValue} 响应正文',
        error,
        stack,
      );
    }
    throw AiMediaGenerationException(
      '${kind.displayName} endpoint returned a non-JSON response.',
      rawResponseBody: body,
    );
  }

  /// 解析 OpenAI 兼容图片响应并持久化为可用于 Markdown 的引用。
  Future<String> _buildMarkdownFromResponse({
    required Map<String, Object?> decoded,
    required String altText,
    Future<void>? cancelSignal,
  }) async {
    final raw = decoded['data'];
    final Iterable<Object?> entries;
    if (raw is List) {
      entries = raw.take(_generatedMediaOutputLimit);
    } else if (raw is Map) {
      final data = stringKeyedMapFromValue(raw);
      entries = <Object?>[
        ..._mediaStrings(
          data['image_urls'],
          limit: _generatedMediaOutputLimit,
        ).map((url) => <String, Object?>{'url': url}),
        ..._mediaStrings(
          data['image_base64'],
          limit: _generatedMediaOutputLimit,
        ).map((value) => <String, Object?>{'b64_json': value}),
      ].take(_generatedMediaOutputLimit);
    } else {
      return '';
    }
    if (entries.isEmpty) return '';
    final buffer = StringBuffer();
    for (final entry in entries) {
      if (entry is! Map) continue;
      final map = entry.cast<String, Object?>();
      // 优先使用服务商返回的 revised_prompt 作为替代文本。
      final effectiveAlt =
          optionalStringFromValue(map['revised_prompt']) ?? altText;
      final b64 = optionalStringFromValue(map['b64_json']);
      if (b64 != null) {
        final md = await saveInlineMediaToMarkdown(
          AiInlineMedia(mimeType: kImagePngMimeType, base64Data: b64),
          label: effectiveAlt,
        );
        if (md.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.writeln();
          buffer.write(md);
        }
        continue;
      }
      final url = optionalStringFromValue(map['url']);
      if (url != null) {
        final bytes = await _downloadBytes(url, cancelSignal: cancelSignal);
        if (bytes != null && bytes.isNotEmpty) {
          final md = await saveInlineMediaToMarkdown(
            AiInlineMedia(
              mimeType: _mimeFromUrl(url),
              base64Data: base64Encode(bytes),
            ),
            label: effectiveAlt,
          );
          if (md.isNotEmpty) {
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.writeln();
            buffer.write(md);
            continue;
          }
        }
        // 下载失败时保留原始地址。
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.writeln();
        final safeAlt = sanitizeMarkdownAltText(effectiveAlt);
        buffer.write('![$safeAlt]($url)');
      }
    }
    return buffer.toString();
  }

  Future<String> _buildMarkdownFromMediaResponse({
    required Map<String, Object?> decoded,
    required _GeneratedMediaKind kind,
    required String label,
    Future<void>? cancelSignal,
  }) async {
    if (kind.isImage) {
      return _buildMarkdownFromResponse(
        decoded: decoded,
        altText: label,
        cancelSignal: cancelSignal,
      );
    }
    final entries = _extractMediaEntries(decoded, kind);
    if (entries.isEmpty) return '';
    final buffer = StringBuffer();
    for (final entry in entries) {
      final effectiveLabel = sanitizeMarkdownAltText(
        nullIfBlank(entry.label) ?? label,
      );
      final base64Data = nullIfBlank(entry.base64Data);
      if (base64Data != null) {
        final md = await saveInlineMediaToMarkdown(
          AiInlineMedia(
            mimeType: entry.mimeType ?? _defaultMimeFor(kind),
            base64Data: base64Data,
          ),
          label: effectiveLabel,
        );
        if (md.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.writeln();
          buffer.write(md);
        }
        continue;
      }
      final url = nullIfBlank(entry.url);
      if (url != null) {
        final localMarkdown = await _downloadRemoteMediaToMarkdown(
          kind: kind,
          url: url,
          label: effectiveLabel,
          cancelSignal: cancelSignal,
        );
        if (localMarkdown.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.writeln();
          buffer.write(localMarkdown);
          continue;
        }
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.writeln();
        buffer.write('[$effectiveLabel]($url)');
      }
    }
    return buffer.toString();
  }

  Future<String> _downloadRemoteMediaToMarkdown({
    required _GeneratedMediaKind kind,
    required String url,
    required String label,
    Future<void>? cancelSignal,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '';
    }
    final inferredMimeType = _mediaMimeFromUrl(url, kind);
    final destination = await createInlineMediaOutputFile(
      mimeType: inferredMimeType,
    );
    try {
      final response = await _transport.downloadToFile(
        uri: uri,
        headers: const <String, String>{},
        timeout: _remoteMediaDownloadTimeout,
        destination: destination,
        maxBytes: kind.isVideo
            ? _videoDownloadMaxBytes
            : _audioResponseMaxBytes,
        maxJsonBytes: _mediaJsonResponseMaxBytes,
        cancelSignal: cancelSignal,
      );
      if (!response.isSuccess ||
          response.bytesWritten <= 0 ||
          response.filePath == null) {
        await _deleteFileIfPresent(destination);
        return '';
      }
      final contentType = responseMimeType(response.headers);
      if (contentType.isNotEmpty &&
          contentType != kApplicationOctetStreamMimeType &&
          !(kind.isVideo && isVideoMimeType(contentType)) &&
          !(kind.isAudio && isAudioMimeType(contentType))) {
        await _deleteFileIfPresent(destination);
        return '';
      }
      final mimeType = kind.isVideo
          ? isVideoMimeType(contentType)
                ? contentType
                : kVideoMp4MimeType
          : isAudioMimeType(contentType)
          ? contentType
          : inferredMimeType;
      return inlineMediaFileMarkdown(
        filePath: response.filePath!,
        mimeType: mimeType,
        label: label,
      );
    } on http.RequestAbortedException {
      await _deleteFileIfPresent(destination);
      throw const AiMediaGenerationCancelledException();
    } catch (error, stack) {
      await _deleteFileIfPresent(destination);
      silentLog('ai_image_generation_service', '下载远程媒体文件', error, stack);
      return '';
    }
  }

  List<_MediaPayloadEntry> _extractMediaEntries(
    Map<String, Object?> decoded,
    _GeneratedMediaKind kind,
  ) {
    final entries = <_MediaPayloadEntry>[];
    final seen = <String>{};

    void collect(
      Object? value, {
      String? label,
      String? mimeType,
      int depth = 0,
    }) {
      if (value == null ||
          entries.length >= _generatedMediaOutputLimit ||
          depth > _mediaPayloadTraversalDepthLimit) {
        return;
      }
      if (value is String) {
        final trimmed = nullIfBlank(value);
        if (trimmed == null) return;
        if (_looksLikeUrl(trimmed) || trimmed.startsWith('file:')) {
          if (seen.add(trimmed)) {
            entries.add(
              _MediaPayloadEntry(
                url: trimmed,
                label: label,
                mimeType: mimeType,
              ),
            );
          }
        } else if (_looksLikeBase64(trimmed)) {
          if (seen.add(trimmed)) {
            entries.add(
              _MediaPayloadEntry(
                base64Data: trimmed,
                label: label,
                mimeType: mimeType,
              ),
            );
          }
        }
        return;
      }
      if (value is List) {
        for (final item in value) {
          if (entries.length >= _generatedMediaOutputLimit) break;
          collect(item, label: label, mimeType: mimeType, depth: depth + 1);
        }
        return;
      }
      if (value is! Map) return;
      final map = stringKeyedMapFromValue(value);
      final nestedLabel = firstNonBlankStringForKeys(map, const <String>[
        'revised_prompt',
        'prompt',
        'caption',
        'transcript',
        'name',
        'title',
      ]);
      final nextLabel = nestedLabel ?? label;
      final nextMimeType = firstNonBlankStringForKeys(map, const <String>[
        'mime_type',
        'mimeType',
        'content_type',
        'contentType',
        'media_type',
        'mediaType',
      ]);
      final effectiveMimeType = nextMimeType ?? mimeType;

      for (final key in _urlKeysFor(kind)) {
        collect(
          map[key],
          label: nextLabel,
          mimeType: effectiveMimeType,
          depth: depth + 1,
        );
      }
      for (final key in _base64KeysFor(kind)) {
        collect(
          map[key],
          label: nextLabel,
          mimeType: effectiveMimeType,
          depth: depth + 1,
        );
      }
      for (final key in const <String>[
        'data',
        'output',
        'result',
        'results',
        'outcome',
        'content',
        'media',
        'medias',
        'media_urls',
        'file',
        'files',
        // GLM CogVideoX 将播放地址放在 video_result 数组中。
        'video_result',
        'videoResult',
        'audio_result',
        'audioResult',
        'image_result',
        'imageResult',
      ]) {
        final nested = map[key];
        if (nested == null || identical(nested, value)) continue;
        collect(
          nested,
          label: nextLabel,
          mimeType: effectiveMimeType,
          depth: depth + 1,
        );
      }
    }

    collect(decoded);
    return List<_MediaPayloadEntry>.unmodifiable(entries);
  }

  List<String> _urlKeysFor(_GeneratedMediaKind kind) {
    return switch (kind) {
      _GeneratedMediaKind.image => const <String>['url', 'image_url'],
      _GeneratedMediaKind.video => const <String>[
        'url',
        'uri',
        'file_url',
        'fileUrl',
        'video',
        'video_url',
        'videoUrl',
        'video_uri',
        'videoUri',
        'remixed_from_video_id',
        'remixedFromVideoId',
        'download_url',
        'downloadUrl',
        'result_url',
        'resultUrl',
      ],
      _GeneratedMediaKind.audio => const <String>[
        'url',
        'uri',
        'file_url',
        'fileUrl',
        'audio',
        'audio_url',
        'audioUrl',
        'audio_uri',
        'audioUri',
        'download_url',
        'downloadUrl',
        'result_url',
        'resultUrl',
      ],
    };
  }

  List<String> _base64KeysFor(_GeneratedMediaKind kind) {
    return switch (kind) {
      _GeneratedMediaKind.image => const <String>['b64_json', 'base64'],
      _GeneratedMediaKind.video => const <String>[
        'b64_json',
        'base64',
        'base64_data',
        'base64Data',
        'video_base64',
        'videoBase64',
      ],
      _GeneratedMediaKind.audio => const <String>[
        'b64_json',
        'base64',
        'base64_data',
        'base64Data',
        'audio_base64',
        'audioBase64',
        'data',
      ],
    };
  }

  bool _looksLikeUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'file');
  }

  bool _looksLikeBase64(String value) {
    final normalized = nullIfBlank(value);
    if (normalized == null || normalized.length < 32) return false;
    return _base64LikePattern.hasMatch(normalized);
  }

  Future<_PolledMediaResult> _pollMediaOperation({
    required String initialUrl,
    required Map<String, Object?> initialPayload,
    required _GeneratedMediaKind kind,
    required String label,
    required AiProtocolType protocol,
    required String modelId,
    required Map<String, String> requestHeaders,
    required Duration timeout,
    AiTokenUsage? initialUsage,
    Future<void>? cancelSignal,
  }) async {
    final operationUrl = _resolveOperationUrl(
      initialUrl,
      initialPayload,
      protocol,
      kind: kind,
      modelId: modelId,
    );
    if (operationUrl == null) {
      return const _PolledMediaResult.empty();
    }
    final deadline = MonotonicDeadline(
      timeout,
      timeoutMessage: '${kind.displayName} 生成轮询超时。',
    );
    var lastBody = jsonEncode(initialPayload);
    var attempt = 0;
    var transientFailures = 0;
    var usage = initialUsage;
    try {
      while (!deadline.isExpired) {
        attempt += 1;
        final remaining = deadline.remainingOrNull();
        if (remaining == null) break;
        // 并行轮询加入有界抖动，避免同时冲击受限端点；长任务在预热后
        // 将单次退避封顶为 5 秒，由统一总时限决定最终退出时刻。
        final wait = _pollDelayForAttempt(attempt);
        if (wait < remaining) {
          await _delayOrThrowCancelled(wait, cancelSignal);
        }
        final requestRemaining = deadline.remainingOrNull();
        // 剩余不足一秒时不再发起必然立即超时的请求。
        if (requestRemaining == null ||
            requestRemaining < _pollMinimumRequestBudget) {
          break;
        }
        final effectiveTimeout = requestRemaining < _pollRequestTimeoutCap
            ? requestRemaining
            : _pollRequestTimeoutCap;
        final pollingHeaders = Map<String, String>.from(requestHeaders)
          ..['accept'] = kApplicationJsonMimeType;
        final response = await _transport.get(
          uri: Uri.parse(operationUrl),
          headers: pollingHeaders,
          timeout: effectiveTimeout,
          maxResponseBytes: _mediaJsonResponseMaxBytes,
          cancelSignal: cancelSignal,
        );
        lastBody = response.body;
        if (isHttpFailureStatus(response.statusCode)) {
          if (isHttpTransientRetryableStatus(response.statusCode) &&
              transientFailures < _transientPollMaxFailures) {
            transientFailures += 1;
            final retryAfter = _parseRetryAfter(
              response.headers['retry-after'],
            );
            final backoff =
                retryAfter ?? _transientPollBackoffDelay(transientFailures);
            final budget = deadline.remainingOrNull();
            if (budget != null && backoff < budget) {
              await _delayOrThrowCancelled(backoff, cancelSignal);
              continue;
            }
          }
          throw AiMediaGenerationException(
            _MediaErrorMessages.httpStatus(
              kind,
              response.statusCode,
              serverMessage: _extractError(response.body),
            ),
            rawResponseBody: response.body,
          );
        }
        transientFailures = 0;
        final decoded = _decodeJsonForKind(response.body, kind);
        final parsedUsage = AiTokenUsageParser.parseResponsePayload(decoded);
        if (parsedUsage != null) {
          usage = AiTokenUsageParser.carryForward(usage, parsedUsage);
        }
        _throwIfMiniMaxProviderFailed(
          decoded,
          kind: kind,
          protocol: protocol,
          rawResponseBody: response.body,
        );
        // MiniMax 视频完成后返回 file_id，需要继续查询实际下载地址。
        if (protocol == AiProtocolType.minimax && kind.isVideo) {
          final status = _operationStatus(decoded);
          if (status == 'success') {
            final fileId = _findFirstString(decoded, const <String>[
              'file_id',
              'fileId',
            ]);
            final lookupTimeout = deadline.remainingOrNull();
            if (fileId != null && lookupTimeout != null) {
              final downloadUrl = await _resolveMiniMaxFileUrl(
                initialUrl: initialUrl,
                fileId: fileId,
                requestHeaders: requestHeaders,
                effectiveTimeout: lookupTimeout,
                cancelSignal: cancelSignal,
              );
              if (downloadUrl != null) {
                final safeLabel = sanitizeMarkdownAltText(label);
                return _PolledMediaResult(
                  markdown: '[$safeLabel]($downloadUrl)',
                  rawResponseBody: response.body,
                  usage: usage,
                );
              }
            }
          }
        }
        final markdown = await _buildMarkdownFromMediaResponse(
          decoded: decoded,
          kind: kind,
          label: label,
          cancelSignal: cancelSignal,
        );
        if (markdown.isNotEmpty) {
          return _PolledMediaResult(
            markdown: markdown,
            rawResponseBody: response.body,
            usage: usage,
          );
        }
        final status = _operationStatus(decoded);
        // Sora 2 和旧版 grok2api 仅通过二进制 content 端点提供最终视频。
        if (kind.isVideo &&
            (protocol == AiProtocolType.openai ||
                (protocol == AiProtocolType.grok &&
                    !_isNativeXaiVideoGenerationUrl(initialUrl))) &&
            !_usesAgnesMediaApi(protocol, modelId) &&
            _isTerminalSuccessStatus(status)) {
          final downloadTimeout = deadline.remainingOrNull();
          if (downloadTimeout == null) break;
          final contentMarkdown = await _downloadSoraStyleVideoContent(
            operationUrl: operationUrl,
            requestHeaders: requestHeaders,
            effectiveTimeout: downloadTimeout,
            label: label,
            cancelSignal: cancelSignal,
          );
          if (contentMarkdown.isNotEmpty) {
            return _PolledMediaResult(
              markdown: contentMarkdown,
              rawResponseBody: response.body,
              usage: usage,
            );
          }
        }
        if (_isTerminalFailureStatus(status)) {
          throw AiMediaGenerationException(
            '${kind.displayName} generation failed: ${_extractError(response.body)}',
            rawResponseBody: response.body,
          );
        }
      }
    } finally {
      deadline.stop();
    }
    throw AiMediaGenerationException(
      _MediaErrorMessages.timeout(kind, timeout),
      rawResponseBody: lastBody,
    );
  }

  /// 从 Sora 2 / 旧版 grok2api 的二进制 content 端点下载最终视频。
  Future<String> _downloadSoraStyleVideoContent({
    required String operationUrl,
    required Map<String, String> requestHeaders,
    required Duration effectiveTimeout,
    required String label,
    Future<void>? cancelSignal,
  }) async {
    final contentUri = Uri.parse(operationUrl).replace(
      pathSegments: <String>[
        ...Uri.parse(
          operationUrl,
        ).pathSegments.where((segment) => segment.isNotEmpty),
        'content',
      ],
    );
    final downloadHeaders = Map<String, String>.from(requestHeaders)
      ..['accept'] = 'video/*, application/octet-stream;q=0.9';
    final downloadTimeout = effectiveTimeout < _soraContentDownloadTimeoutCap
        ? effectiveTimeout
        : _soraContentDownloadTimeoutCap;
    final destination = await createInlineMediaOutputFile(
      mimeType: kVideoMp4MimeType,
    );
    final response = await _transport.downloadToFile(
      uri: contentUri,
      headers: downloadHeaders,
      timeout: downloadTimeout,
      destination: destination,
      maxBytes: _videoDownloadMaxBytes,
      maxJsonBytes: _mediaJsonResponseMaxBytes,
      cancelSignal: cancelSignal,
    );
    if (!response.isSuccess) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.httpStatus(
          _GeneratedMediaKind.video,
          response.statusCode,
          serverMessage: _extractError(response.errorBody),
          contextHint: 'GET /content',
        ),
        rawResponseBody: response.errorBody,
      );
    }
    final filePath = response.filePath;
    if (response.bytesWritten == 0 || filePath == null) {
      await _deleteFileIfPresent(destination);
      return '';
    }
    final mimeType = responseMimeType(response.headers);
    if (isJsonMimeType(mimeType)) {
      try {
        final body = await readBoundedFileString(
          File(filePath),
          maxBytes: _mediaJsonResponseMaxBytes,
        );
        throw AiMediaGenerationException(
          'Video content endpoint returned JSON instead of media: '
          '${_extractError(body)}',
          rawResponseBody: body,
        );
      } finally {
        await _deleteFileIfPresent(destination);
      }
    }
    final effectiveMime = isVideoMimeType(mimeType)
        ? mimeType
        : kVideoMp4MimeType;
    return inlineMediaFileMarkdown(
      filePath: filePath,
      mimeType: effectiveMime,
      label: label,
    );
  }

  /// MiniMax 视频完成后通过独立的 `/v1/files/retrieve` 查询下载地址。
  Future<String?> _resolveMiniMaxFileUrl({
    required String initialUrl,
    required String fileId,
    required Map<String, String> requestHeaders,
    required Duration effectiveTimeout,
    Future<void>? cancelSignal,
  }) async {
    final base = Uri.parse(initialUrl);
    final segments = base.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    while (segments.isNotEmpty &&
        segments.last.toLowerCase() != 'video_generation') {
      segments.removeLast();
    }
    if (segments.isNotEmpty) segments.removeLast();
    segments.addAll(const <String>['files', 'retrieve']);
    final retrieveUri = base.replace(
      pathSegments: segments,
      queryParameters: <String, String>{'file_id': fileId},
    );
    final pollingHeaders = Map<String, String>.from(requestHeaders)
      ..['accept'] = kApplicationJsonMimeType;
    final deadline = MonotonicDeadline(
      effectiveTimeout,
      timeoutMessage: 'MiniMax 视频文件查询超时。',
    );
    http.Response? response;
    try {
      for (var i = 0; i < _miniMaxFileRetrieveAttempts; i++) {
        final requestBudget = deadline.remainingOrNull();
        if (requestBudget == null ||
            requestBudget < _pollMinimumRequestBudget) {
          return null;
        }
        response = await _transport.get(
          uri: retrieveUri,
          headers: pollingHeaders,
          timeout: requestBudget < _pollRequestTimeoutCap
              ? requestBudget
              : _pollRequestTimeoutCap,
          maxResponseBytes: _mediaJsonResponseMaxBytes,
          cancelSignal: cancelSignal,
        );
        if (isHttpSuccessStatus(response.statusCode)) break;
        if (!isHttpTransientRetryableStatus(response.statusCode) ||
            i == _miniMaxFileRetrieveAttempts - 1) {
          return null;
        }
        final retryAfter = _parseRetryAfter(response.headers['retry-after']);
        final backoff = retryAfter ?? _miniMaxFileRetrieveBackoffDelay();
        final retryBudget = deadline.remainingOrNull();
        if (retryBudget == null || backoff >= retryBudget) return null;
        await _delayOrThrowCancelled(backoff, cancelSignal);
      }
    } finally {
      deadline.stop();
    }
    if (response == null || isHttpFailureStatus(response.statusCode)) {
      return null;
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final payload = stringKeyedMapFromValue(decoded);
        _throwIfMiniMaxProviderFailed(
          payload,
          kind: _GeneratedMediaKind.video,
          protocol: AiProtocolType.minimax,
          rawResponseBody: response.body,
        );
        final url = _findFirstString(payload, const <String>[
          'download_url',
          'downloadUrl',
          'backup_download_url',
          'file_url',
          'fileUrl',
          'url',
        ]);
        return nullIfBlank(url);
      }
    } catch (error, stack) {
      silentLog(
        'ai_image_generation_service',
        '解析 MiniMax /files/retrieve 响应',
        error,
        stack,
      );
    }
    return null;
  }

  static final math.Random _pollJitter = math.Random();

  Duration _pollDelayForAttempt(int attempt) {
    final baseMs = switch (attempt) {
      < _pollWarmupAttemptLimit => _pollWarmupDelayMs,
      < _pollSteadyAttemptLimit => _pollSteadyDelayMs,
      _ => _pollMaxDelayMs,
    };
    final jitterMs =
        _pollJitter.nextInt(_pollJitterWindowMs) - _pollJitterHalfWindowMs;
    return Duration(milliseconds: math.max(_pollMinDelayMs, baseMs + jitterMs));
  }

  Duration _transientPollBackoffDelay(int transientFailures) {
    return exponentialBackoffDuration(
          attempt: transientFailures,
          base: _transientPollBackoffBase,
          cap: _transientPollBackoffCap,
        ) +
        Duration(milliseconds: _pollJitter.nextInt(_pollJitterWindowMs));
  }

  Duration _miniMaxFileRetrieveBackoffDelay() {
    return Duration(
      milliseconds:
          _miniMaxFileRetrieveRetryBaseMs +
          _pollJitter.nextInt(_pollJitterWindowMs),
    );
  }

  /// 解析秒数或 HTTP 日期格式的 Retry-After；无效时返回空。
  static Duration? _parseRetryAfter(String? raw) {
    final trimmed = nullIfBlank(raw);
    if (trimmed == null) return null;
    final seconds = optionalNonNegativeIntFromValue(trimmed);
    if (seconds != null) {
      // 单次等待最多 30 秒，避免异常服务端占满任务总时限。
      final cappedSeconds = math.min(seconds, _retryAfterDelayCap.inSeconds);
      return Duration(seconds: cappedSeconds);
    }
    try {
      final when = HttpDate.parse(trimmed);
      final delta = when.toUtc().difference(DateTime.now().toUtc());
      if (delta.isNegative) return Duration.zero;
      if (delta > _retryAfterDelayCap) {
        return _retryAfterDelayCap;
      }
      return delta;
    } catch (_) {
      return null;
    }
  }

  String? _resolveOperationUrl(
    String initialUrl,
    Map<String, Object?> payload,
    AiProtocolType protocol, {
    required _GeneratedMediaKind kind,
    required String modelId,
  }) {
    final explicitUrl = _findFirstString(payload, const <String>[
      'status_url',
      'statusUrl',
      'polling_url',
      'pollingUrl',
      'operation_url',
      'operationUrl',
      'task_url',
      'taskUrl',
    ]);
    if (explicitUrl != null) {
      final parsed = Uri.tryParse(explicitUrl);
      if (parsed != null && parsed.hasScheme) {
        return explicitUrl;
      }
      return Uri.parse(initialUrl).resolve(explicitUrl).toString();
    }
    if (kind.isVideo && _usesAgnesMediaApi(protocol, modelId)) {
      final videoId = _findFirstString(payload, const <String>[
        'video_id',
        'videoId',
        'task_id',
        'taskId',
        'id',
      ]);
      if (videoId == null) return null;
      final uri = Uri.parse(initialUrl);
      return uri
          .replace(
            pathSegments: const <String>['agnesapi'],
            queryParameters: <String, String>{
              'video_id': videoId,
              'model_name': modelId,
            },
          )
          .toString();
    }
    final id = _findFirstString(payload, const <String>[
      'request_id',
      'requestId',
      'id',
      'task_id',
      'taskId',
      'job_id',
      'jobId',
      'operation_id',
      'operationId',
    ]);
    if (id == null) return null;
    final uri = Uri.parse(initialUrl);
    return switch (protocol) {
      AiProtocolType.grok when _isNativeXaiVideoGenerationUrl(initialUrl) =>
        () {
          final segments = uri.pathSegments
              .where((segment) => segment.isNotEmpty)
              .toList(growable: true);
          if (segments.isNotEmpty && segments.last == 'generations') {
            segments.removeLast();
          }
          segments.add(id);
          return uri.replace(pathSegments: segments).toString();
        }(),
      // GLM CogVideoX 异步结果路径。
      AiProtocolType.glm => () {
        final segments = uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .toList(growable: true);
        // 移除生成路径尾段后拼接异步结果标识。
        while (segments.isNotEmpty) {
          final last = segments.last.toLowerCase();
          if (last == 'generations' ||
              last == 'videos' ||
              last == 'images' ||
              last == 'speech') {
            segments.removeLast();
            continue;
          }
          break;
        }
        segments
          ..add('async-result')
          ..add(id);
        return uri.replace(pathSegments: segments).toString();
      }(),
      // MiniMax 通过查询参数获取视频任务状态。
      AiProtocolType.minimax => () {
        final segments = uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .toList(growable: true);
        if (segments.isNotEmpty) segments.removeLast();
        segments
          ..add('query')
          ..add('video_generation');
        return uri
            .replace(
              pathSegments: segments,
              queryParameters: <String, String>{'task_id': id},
            )
            .toString();
      }(),
      // 通义兼容地址无法可靠还原原生任务路径，交由网关按默认路径重定向。
      _ => () {
        final segments =
            uri.pathSegments
                .where((segment) => segment.isNotEmpty)
                .toList(growable: true)
              ..add(id);
        return uri.replace(pathSegments: segments).toString();
      }(),
    };
  }

  String? _findFirstString(Map<String, Object?> map, List<String> keys) {
    var visitedMaps = 0;

    String? search(Map<String, Object?> current, int depth) {
      if (depth > _mediaPayloadTraversalDepthLimit ||
          visitedMaps >= _mediaPayloadMapVisitLimit) {
        return null;
      }
      visitedMaps += 1;
      for (final key in keys) {
        final value = current[key];
        if (value is String) {
          final normalized = nullIfBlank(value);
          if (normalized != null) return normalized;
        }
      }
      for (final value in current.values) {
        if (value is! Map) continue;
        final nested = search(stringKeyedMapFromValue(value), depth + 1);
        if (nested != null) return nested;
      }
      return null;
    }

    return search(map, 0);
  }

  bool _isNativeXaiVideoGenerationUrl(String value) {
    final segments = Uri.tryParse(value)?.pathSegments
        .where((segment) => segment.isNotEmpty)
        .map((segment) => segment.toLowerCase())
        .toList(growable: false);
    return segments != null &&
        segments.length >= 2 &&
        segments[segments.length - 2] == 'videos' &&
        segments.last == 'generations';
  }

  List<String> _mediaStrings(Object? value, {required int limit}) {
    if (value is! List) return const <String>[];
    return value
        .take(limit)
        .map(optionalStringFromValue)
        .whereType<String>()
        .toList(growable: false);
  }

  void _throwIfMiniMaxProviderFailed(
    Map<String, Object?> payload, {
    required _GeneratedMediaKind kind,
    required AiProtocolType protocol,
    required String rawResponseBody,
  }) {
    if (protocol != AiProtocolType.minimax) return;
    final baseResponse = AiOperationHttp.stringKeyedMap(payload['base_resp']);
    final statusCode = optionalIntFromValue(baseResponse['status_code']);
    if (statusCode == null || statusCode == 0) return;
    final statusMessage =
        optionalStringFromValue(baseResponse['status_msg']) ??
        'MiniMax request failed.';
    throw AiMediaGenerationException(
      '${kind.displayName} generation failed ($statusCode): $statusMessage',
      rawResponseBody: rawResponseBody,
    );
  }

  String _operationStatus(Map<String, Object?> payload) {
    final status = _findFirstString(payload, const <String>[
      'status',
      'state',
      'task_status',
      'taskStatus',
      'job_status',
      'jobStatus',
    ]);
    return optionalLowercaseStringFromValue(status) ?? '';
  }

  bool _isTerminalFailureStatus(String status) {
    return status == 'failed' ||
        status == 'failure' ||
        status == 'error' ||
        status == 'expired' ||
        status == 'cancelled' ||
        status == 'canceled';
  }

  /// 判断媒体任务是否成功结束。
  bool _isTerminalSuccessStatus(String status) {
    return status == 'completed' ||
        status == 'complete' ||
        status == 'succeeded' ||
        status == 'success' ||
        status == 'done' ||
        status == 'finished' ||
        status == 'ready';
  }

  Future<String> _saveBinaryMediaBytes({
    required _GeneratedMediaKind kind,
    required List<int> bytes,
    required String mimeType,
    required String label,
  }) async {
    if (bytes.isEmpty) return '';
    return saveInlineMediaToMarkdown(
      AiInlineMedia(
        mimeType: nullIfBlank(mimeType) ?? _defaultMimeFor(kind),
        base64Data: base64Encode(bytes),
      ),
      label: label,
    );
  }

  Future<void> _deleteFileIfPresent(File file) async {
    try {
      if (await isRegularFilePath(file.path)) {
        await file.delete().timeout(defaultBoundedFileReadIdleTimeout);
      }
    } on FileSystemException {
      // 空文件或无效生成媒体仅做尽力清理。
    } on TimeoutException {
      // 清理超时不覆盖原始生成结果。
    }
  }

  bool _isBinaryMediaContentType(String contentType, _GeneratedMediaKind kind) {
    if (contentType.isEmpty || isJsonMimeType(contentType)) {
      return false;
    }
    if (kind.isVideo) return isVideoMimeType(contentType);
    if (kind.isAudio) return isAudioMimeType(contentType);
    if (kind.isImage) return isImageMimeType(contentType);
    return false;
  }

  String _defaultMimeFor(_GeneratedMediaKind kind) {
    return switch (kind) {
      _GeneratedMediaKind.image => kImagePngMimeType,
      _GeneratedMediaKind.video => kVideoMp4MimeType,
      _GeneratedMediaKind.audio => kAudioMpegMimeType,
    };
  }

  Future<List<int>?> _downloadBytes(
    String url, {
    Future<void>? cancelSignal,
  }) async {
    try {
      return await _transport.downloadBytes(
        uri: Uri.parse(url),
        headers: const <String, String>{},
        timeout: _remoteMediaDownloadTimeout,
        cancelSignal: cancelSignal,
      );
    } on http.RequestAbortedException {
      throw const AiMediaGenerationCancelledException();
    } catch (error, stack) {
      silentLog('ai_image_generation_service', '获取远程图片字节', error, stack);
    }
    return null;
  }

  Future<void> _delayOrThrowCancelled(
    Duration delay,
    Future<void>? cancelSignal,
  ) async {
    if (await delayUntilCancelled(delay, cancelSignal: cancelSignal)) {
      throw const AiMediaGenerationCancelledException();
    }
  }

  String _mimeFromUrl(String url) {
    // 仅解析 URL 路径，避免查询参数或无关后缀造成误判。
    final parsedPath = Uri.tryParse(url)?.path;
    final path = parsedPath != null
        ? lowercaseStringFromValue(parsedPath)
        : lowercaseStringFromValue(url);
    if (path.endsWith('.png')) return kImagePngMimeType;
    if (path.endsWith('.webp')) return kImageWebpMimeType;
    if (path.endsWith('.gif')) return kImageGifMimeType;
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      return kImageJpegMimeType;
    }
    return kImagePngMimeType;
  }

  String _mediaMimeFromUrl(String url, _GeneratedMediaKind kind) {
    final path = lowercaseStringFromValue(Uri.tryParse(url)?.path ?? url);
    if (kind.isAudio) {
      if (path.endsWith('.wav')) return kAudioWavMimeType;
      if (path.endsWith('.aac')) return kAudioAacMimeType;
      if (path.endsWith('.ogg') || path.endsWith('.opus')) {
        return kAudioOggMimeType;
      }
      if (path.endsWith('.flac')) return kAudioFlacMimeType;
    } else if (kind.isVideo && path.endsWith('.webm')) {
      return kVideoWebmMimeType;
    }
    return _defaultMimeFor(kind);
  }

  String _extractError(String body) {
    return extractApiErrorMessage(body, emptyFallback: 'Unknown error');
  }

  void dispose() {
    _transport.dispose();
  }
}

class _PixelSize {
  const _PixelSize({required this.width, required this.height});

  final int width;
  final int height;
}

class _MediaPayloadEntry {
  const _MediaPayloadEntry({
    this.url,
    this.base64Data,
    this.label,
    this.mimeType,
  });

  final String? url;
  final String? base64Data;
  final String? label;
  final String? mimeType;
}

class _PolledMediaResult {
  const _PolledMediaResult({
    required this.markdown,
    required this.rawResponseBody,
    this.usage,
  });

  const _PolledMediaResult.empty()
    : markdown = '',
      rawResponseBody = '',
      usage = null;

  final String markdown;
  final String rawResponseBody;
  final AiTokenUsage? usage;
}

/// 媒体错误文案统一委托给公共传输诊断消息，并附加媒体类型。
class _MediaErrorMessages {
  _MediaErrorMessages._();

  static String _label(_GeneratedMediaKind kind) =>
      '${kind.displayName} (${kind.storageValue})';

  static String handshake(_GeneratedMediaKind kind, HandshakeException e) =>
      AiTransportDiagnosticMessages.handshake(e, contextLabel: _label(kind));

  static String tls(_GeneratedMediaKind kind, TlsException e) =>
      AiTransportDiagnosticMessages.tls(e, contextLabel: _label(kind));

  static String socket(_GeneratedMediaKind kind, SocketException e) =>
      AiTransportDiagnosticMessages.socket(e, contextLabel: _label(kind));

  static String httpClient(_GeneratedMediaKind kind, http.ClientException e) =>
      AiTransportDiagnosticMessages.httpClient(e, contextLabel: _label(kind));

  static String response(_GeneratedMediaKind kind, HttpException error) =>
      '${kind.displayName} response could not be processed: ${error.message}';

  static String timeout(_GeneratedMediaKind kind, Duration limit) =>
      AiTransportDiagnosticMessages.timeout(limit, contextLabel: _label(kind));

  static String httpStatus(
    _GeneratedMediaKind kind,
    int code, {
    String serverMessage = '',
    String contextHint = '',
  }) => AiTransportDiagnosticMessages.httpStatus(
    code,
    serverMessage: serverMessage,
    contextLabel: _label(kind),
    contextHint: contextHint,
  );
}
