import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../model/ai_creation_mode.dart';
import '../../model/ai_model_catalog.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../chat/ai_protocol_adapter.dart';
import '../chat/ai_transport_diagnostic_messages.dart';

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

const Set<String> _jsonContentTypes = <String>{
  'application/json',
  'application/x-json',
  'text/json',
};

/// Outcome of a generative multimedia request (image/video/audio).
///
/// The [markdown] field contains assistant-ready markdown (e.g.
/// `![prompt](file:///tmp/openhand_media_xxx/image_1.png)`) which the UI can
/// drop straight into the chat. [attachments] carry the on-disk locations so
/// downstream code may persist or re-render the media through
/// `AiMessageAttachment` later.
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

/// Service that routes image, video and audio generation requests to the
/// correct vendor endpoint.
///
/// This intentionally lives outside [AiProtocolAdapter] because the
/// /v1/images/generations endpoint is only loosely related to chat
/// completions: it has its own body shape, no streaming, and different
/// response handling. Keeping it isolated also lets us evolve per-vendor
/// quirks (Qwen's `qwen-image` aliasing, Grok's `grok-image-1.0`,
/// DALL·E 3's quality/style flags, …) without destabilising the chat path.
class AiImageGenerationService {
  AiImageGenerationService({http.Client? client})
    : _client = client ?? SystemProxyResolver.instance.createHttpClient();

  final http.Client _client;

  /// Returns `true` when [protocol] is known to speak the OpenAI-compatible
  /// images/generations HTTP contract. Gemini returns images inline through
  /// the chat endpoint (responseModalities) and is handled separately.
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
      case AiProtocolType.joycode:
      case AiProtocolType.wenxin:
      case AiProtocolType.meta:
      case AiProtocolType.mimo:
      case AiProtocolType.hunyuan:
      case AiProtocolType.vllm:
      case AiProtocolType.sglang:
      case AiProtocolType.ollama:
        return true;
      case AiProtocolType.gemini:
      case AiProtocolType.claude:
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
      // Grok via chenyme/grok2api gateway exposes `POST /v1/videos`
      // (multipart) for `grok-imagine-video`. xAI native Grok API has no
      // public video endpoint, so this branch only activates when users
      // route through grok2api (they configure baseUrl accordingly).
      case AiProtocolType.grok:
        return true;
      // Hunyuan video uses Tencent Cloud's TC3-HMAC signed RPC at
      // hunyuan.tencentcloudapi.com — incompatible with OpenAI-shape POST
      // and bearer auth. Wenxin/StepFun likewise lack public OpenAI-compat
      // video endpoints. Re-enable when dedicated adapters land.
      case AiProtocolType.hunyuan:
      case AiProtocolType.stepfun:
      case AiProtocolType.wenxin:
      case AiProtocolType.gemini:
      case AiProtocolType.claude:
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
      AiModelCapability.imageGeneration,
      protocolSupported: supportsImageGeneration(model.protocolType),
    );
  }

  static bool supportsVideoGenerationForModel(AiModelConfig model) {
    return _supportsGenerationCapabilityForModel(
      model,
      AiModelCapability.videoGeneration,
      protocolSupported: supportsVideoGeneration(model.protocolType),
    );
  }

  static bool supportsAudioGenerationForModel(AiModelConfig model) {
    return _supportsGenerationCapabilityForModel(
      model,
      AiModelCapability.audioGeneration,
      protocolSupported: supportsAudioGeneration(model.protocolType),
    );
  }

  static bool _supportsGenerationCapabilityForModel(
    AiModelConfig model,
    AiModelCapability capability, {
    required bool protocolSupported,
  }) {
    final profile = model.profileFor(model.modelId);
    if (profile.capabilities.isNotEmpty) {
      return profile.capabilities.contains(capability);
    }
    final catalog = AiModelCatalog.lookup(model.modelId, model.protocolType);
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
        return true;
      // StepFun, Wenxin, Hunyuan, Seed (Volcengine TTS) all use bespoke
      // signed-RPC APIs rather than `/v1/audio/speech`. Re-enable when a
      // dedicated adapter lands.
      case AiProtocolType.seed:
      case AiProtocolType.stepfun:
      case AiProtocolType.wenxin:
      case AiProtocolType.hunyuan:
      case AiProtocolType.gemini:
      case AiProtocolType.claude:
      case AiProtocolType.deepseek:
      case AiProtocolType.kimi:
      case AiProtocolType.grok:
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

  /// Returns the model id to use for image generation. The user is expected
  /// to configure an image-capable model directly in their provider settings.
  static String resolveImageModelId(AiModelConfig model, AiCreationMode mode) {
    return model.modelId.trim();
  }

  static String resolveVideoModelId(AiModelConfig model) {
    return model.modelId.trim();
  }

  static String resolveAudioModelId(AiModelConfig model) {
    return model.modelId.trim();
  }

  /// Generates one or more images via an OpenAI-compatible
  /// `/v1/images/generations` endpoint and returns a [AiMediaGenerationResult]
  /// whose markdown can be inlined into an assistant bubble.
  ///
  /// Throws [AiMediaGenerationException] for any transport or decoding error.
  Future<AiMediaGenerationResult> generateImage({
    required AiModelConfig model,
    required String prompt,
    AiCreationOptions options = AiCreationOptions.empty,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (!supportsImageGenerationForModel(model)) {
      throw AiMediaGenerationException(
        'Image generation is not implemented for protocol '
        '${model.protocolType.storageValue}.',
      );
    }
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      throw const AiMediaGenerationException(
        'Refusing to call the image endpoint with an empty prompt.',
      );
    }
    final imageModelId = resolveImageModelId(model, AiCreationMode.image);
    final url = _resolveImagesEndpoint(model.normalizedBaseUrl);
    final headers = _buildHeaders(model);
    final body = _buildImageBody(
      modelId: imageModelId,
      prompt: trimmedPrompt,
      options: options,
      protocol: model.protocolType,
    );
    final startedAt = DateTime.now().toUtc();
    final http.Response response;
    try {
      response = await _client
          .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
          .timeout(timeout);
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
    } on http.ClientException catch (error) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.httpClient(_GeneratedMediaKind.image, error),
      );
    }
    final endedAt = DateTime.now().toUtc();
    if (response.statusCode < 200 || response.statusCode >= 300) {
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
    final markdown = await _buildMarkdownFromResponse(
      decoded: decoded,
      altText: trimmedPrompt,
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
      requestUrl: url,
      requestBody: body,
      requestHeaders: Map<String, String>.unmodifiable(headers),
      startedAt: startedAt,
      endedAt: endedAt,
    );
  }

  Future<AiMediaGenerationResult> generateVideo({
    required AiModelConfig model,
    required String prompt,
    AiCreationOptions options = AiCreationOptions.empty,
    Duration timeout = const Duration(minutes: 15),
  }) {
    return _generateMedia(
      kind: _GeneratedMediaKind.video,
      model: model,
      prompt: prompt,
      options: options,
      timeout: timeout,
    );
  }

  Future<AiMediaGenerationResult> generateAudio({
    required AiModelConfig model,
    required String prompt,
    AiCreationOptions options = AiCreationOptions.empty,
    Duration timeout = const Duration(minutes: 3),
  }) {
    return _generateMedia(
      kind: _GeneratedMediaKind.audio,
      model: model,
      prompt: prompt,
      options: options,
      timeout: timeout,
    );
  }

  Future<AiMediaGenerationResult> _generateMedia({
    required _GeneratedMediaKind kind,
    required AiModelConfig model,
    required String prompt,
    required AiCreationOptions options,
    required Duration timeout,
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
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      throw AiMediaGenerationException(
        'Refusing to call the ${kind.storageValue} endpoint with an empty prompt.',
      );
    }
    final modelId = switch (kind) {
      _GeneratedMediaKind.image => resolveImageModelId(
        model,
        AiCreationMode.image,
      ),
      _GeneratedMediaKind.video => resolveVideoModelId(model),
      _GeneratedMediaKind.audio => resolveAudioModelId(model),
    };
    final url = _resolveMediaEndpoint(
      model.normalizedBaseUrl,
      kind,
      model.protocolType,
    );
    final headers = _buildHeaders(model);
    if (!model.customHeaders.keys.any(
      (key) => key.trim().toLowerCase() == 'accept',
    )) {
      headers['accept'] = _acceptHeaderFor(kind);
    }
    // DashScope (Qwen) video generation is async-by-design: the request must
    // carry `X-DashScope-Async: enable` to be queued, otherwise it 400s
    // with `InvalidParameter`. Inject only when the user has not already
    // overridden the header.
    if (kind.isVideo && model.protocolType == AiProtocolType.qwen) {
      final hasOverride = model.customHeaders.keys.any(
        (key) => key.trim().toLowerCase() == 'x-dashscope-async',
      );
      if (!hasOverride) {
        headers['x-dashscope-async'] = 'enable';
      }
    }
    final body = _buildMediaBody(
      kind: kind,
      modelId: modelId,
      prompt: trimmedPrompt,
      options: options,
      protocol: model.protocolType,
    );
    final useMultipart = _videoEndpointWantsMultipart(
      kind: kind,
      protocol: model.protocolType,
    );
    final startedAt = DateTime.now().toUtc();
    final http.Response response;
    try {
      if (useMultipart) {
        // OpenAI Sora 2 (and OpenAI-compatible gateways such as grok2api)
        // require multipart/form-data for `POST /v1/videos`. Sending a
        // JSON body causes the server to see all fields as missing because
        // the FastAPI form parser cannot decode JSON.
        response = await _postMultipartMediaRequest(
          uri: Uri.parse(url),
          headers: headers,
          body: body,
          timeout: timeout,
        );
      } else {
        response = await _client
            .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
            .timeout(timeout);
      }
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
      throw AiMediaGenerationException(
        _MediaErrorMessages.socket(kind, error),
      );
    } on http.ClientException catch (error) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.httpClient(kind, error),
      );
    }
    final endedAt = DateTime.now().toUtc();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.httpStatus(
          kind,
          response.statusCode,
          serverMessage: _extractError(response.body),
        ),
        rawResponseBody: response.body,
      );
    }

    final contentType = _responseContentType(response.headers);
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
        requestUrl: url,
        requestBody: body,
        requestHeaders: Map<String, String>.unmodifiable(headers),
        startedAt: startedAt,
        endedAt: endedAt,
      );
    }

    final decoded = _decodeJsonForKind(response.body, kind);
    final initialMarkdown = await _buildMarkdownFromMediaResponse(
      decoded: decoded,
      kind: kind,
      label: trimmedPrompt,
    );
    if (initialMarkdown.isNotEmpty) {
      return AiMediaGenerationResult(
        markdown: initialMarkdown,
        rawResponseBody: response.body,
        requestUrl: url,
        requestBody: body,
        requestHeaders: Map<String, String>.unmodifiable(headers),
        startedAt: startedAt,
        endedAt: endedAt,
      );
    }

    final polled = await _pollMediaOperation(
      initialUrl: url,
      initialPayload: decoded,
      kind: kind,
      label: trimmedPrompt,
      protocol: model.protocolType,
      requestHeaders: headers,
      timeout: timeout,
      startedAt: startedAt,
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
      requestUrl: url,
      requestBody: body,
      requestHeaders: Map<String, String>.unmodifiable(headers),
      startedAt: startedAt,
      endedAt: DateTime.now().toUtc(),
    );
  }

  String _resolveImagesEndpoint(String baseUrl) {
    if (baseUrl.trim().isEmpty) {
      throw const AiMediaGenerationException('Missing base URL.');
    }
    // The chat base URL often ends in `.../v1/chat/completions`.  We want
    // `.../v1/images/generations` — trim trailing chat-style suffixes and
    // append the images path.
    var uri = Uri.parse(baseUrl);
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    while (segments.isNotEmpty) {
      final last = segments.last.toLowerCase();
      if (last == 'completions' ||
          last == 'chat' ||
          last == 'chat/completions' ||
          last == 'responses') {
        segments.removeLast();
        continue;
      }
      break;
    }
    // If a `v1` (or equivalent) prefix is missing entirely, add one so the
    // path is `/v1/images/generations`.
    if (segments.isEmpty ||
        !_isApiVersionSegment(segments.last.toLowerCase())) {
      // Walk back to find an existing version segment; otherwise append v1.
      final idx = segments.lastIndexWhere(
        (segment) => _isApiVersionSegment(segment.toLowerCase()),
      );
      if (idx < 0) {
        segments.add('v1');
      }
    }
    segments
      ..add('images')
      ..add('generations');
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: segments,
      query: uri.query.isEmpty ? null : uri.query,
    ).toString();
  }

  String _resolveMediaEndpoint(
    String baseUrl,
    _GeneratedMediaKind kind,
    AiProtocolType protocol,
  ) {
    if (kind.isImage) return _resolveImagesEndpoint(baseUrl);
    if (baseUrl.trim().isEmpty) {
      throw const AiMediaGenerationException('Missing base URL.');
    }
    final uri = Uri.parse(baseUrl);
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    if (_looksLikeMediaEndpoint(segments, kind)) {
      return baseUrl;
    }
    while (segments.isNotEmpty) {
      final last = segments.last.toLowerCase();
      if (last == 'completions' ||
          last == 'chat' ||
          last == 'responses' ||
          last == 'generations' ||
          last == 'speech') {
        segments.removeLast();
        continue;
      }
      break;
    }
    if (segments.isEmpty ||
        !_isApiVersionSegment(segments.last.toLowerCase())) {
      final idx = segments.lastIndexWhere(
        (segment) => _isApiVersionSegment(segment.toLowerCase()),
      );
      if (idx < 0) {
        segments.add('v1');
      }
    }
    segments.addAll(_mediaEndpointSuffix(kind, protocol));
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: segments,
      query: uri.query.isEmpty ? null : uri.query,
    ).toString();
  }

  bool _looksLikeMediaEndpoint(
    List<String> segments,
    _GeneratedMediaKind kind,
  ) {
    final lowered = segments.map((segment) => segment.toLowerCase()).toList();
    if (lowered.isEmpty) return false;
    if (kind.isVideo) {
      return lowered.any(
        (segment) => segment.contains('video') || segment.contains('veo'),
      );
    }
    if (kind.isAudio) {
      return lowered.any(
        (segment) =>
            segment.contains('audio') ||
            segment.contains('speech') ||
            segment.contains('tts') ||
            segment.contains('voice'),
      );
    }
    return false;
  }

  List<String> _mediaEndpointSuffix(
    _GeneratedMediaKind kind,
    AiProtocolType protocol,
  ) {
    if (kind.isVideo) {
      return switch (protocol) {
        // OpenAI Sora 2 exposes `POST /v1/videos` (returns a job; poll via
        // `/v1/videos/{id}` and download `/v1/videos/{id}/content`).
        AiProtocolType.openai => const <String>['videos'],
        // grok2api gateway mirrors OpenAI Sora's `/v1/videos` async layout.
        AiProtocolType.grok => const <String>['videos'],
        // MiniMax uses a flat `POST /v1/video_generation` instead of the
        // OpenAI-style nested `videos/generations` path.
        AiProtocolType.minimax => const <String>['video_generation'],
        // GLM/Zhipu BigModel: `POST /api/paas/v4/videos/generations`.
        // Qwen DashScope compatible-mode also accepts `/videos/generations`
        // as a passthrough to the native video-synthesis service.
        _ => const <String>['videos', 'generations'],
      };
    }
    if (kind.isAudio) {
      return switch (protocol) {
        // MiniMax T2A v2 endpoint.
        AiProtocolType.minimax => const <String>['t2a_v2'],
        _ => const <String>['audio', 'speech'],
      };
    }
    return const <String>['images', 'generations'];
  }

  bool _isApiVersionSegment(String segment) {
    return segment == 'v1' ||
        segment == 'v2' ||
        segment == 'v3' ||
        segment == 'v4' ||
        RegExp(r'^v[0-9]+(beta|alpha)?$').hasMatch(segment);
  }

  Map<String, String> _buildHeaders(AiModelConfig model) {
    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    final rawToken = model.token.trim();
    if (rawToken.isNotEmpty && model.authScheme != AiAuthScheme.none) {
      if (model.authScheme == AiAuthScheme.apiKey) {
        headers['x-api-key'] = model.authScheme.apply(rawToken);
      } else {
        headers['authorization'] = model.authScheme.apply(rawToken);
      }
    }
    // Merge user-defined custom headers last so they can override defaults.
    for (final entry in model.customHeaders.entries) {
      final key = entry.key.trim();
      if (key.isNotEmpty) {
        headers[key] = entry.value;
      }
    }
    return headers;
  }

  String _acceptHeaderFor(_GeneratedMediaKind kind) {
    return switch (kind) {
      _GeneratedMediaKind.image => 'application/json',
      _GeneratedMediaKind.video => 'application/json, video/*;q=0.9',
      _GeneratedMediaKind.audio => 'application/json, audio/*;q=0.9',
    };
  }

  /// Returns `true` when the destination video endpoint expects
  /// `multipart/form-data` instead of `application/json`.
  ///
  /// OpenAI Sora 2's `POST /v1/videos` is documented as multipart, and
  /// OpenAI-compatible gateways (notably `chenyme/grok2api`) only parse
  /// the request via FastAPI's `Form()` extractor — sending JSON yields
  /// `model: missing, prompt: missing, input: None`.
  bool _videoEndpointWantsMultipart({
    required _GeneratedMediaKind kind,
    required AiProtocolType protocol,
  }) {
    if (!kind.isVideo) return false;
    // Both OpenAI Sora 2 and grok2api expose `POST /v1/videos` as multipart
    // form-data — JSON body yields `model/prompt missing, input: None`.
    return protocol == AiProtocolType.openai || protocol == AiProtocolType.grok;
  }

  Future<http.Response> _postMultipartMediaRequest({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required Duration timeout,
  }) async {
    final request = http.MultipartRequest('POST', uri);
    headers.forEach((key, value) {
      // Let MultipartRequest set its own boundary-aware Content-Type;
      // forward auth/accept/custom headers verbatim.
      if (key.trim().toLowerCase() == 'content-type') return;
      request.headers[key] = value;
    });
    body.forEach((key, value) {
      if (value == null) return;
      // Multipart fields are strings only; arrays/maps must be serialized.
      final fieldValue = value is String
          ? value
          : (value is num || value is bool
                ? value.toString()
                : jsonEncode(value));
      request.fields[key] = fieldValue;
    });
    final streamed = await _client.send(request).timeout(timeout);
    return http.Response.fromStream(streamed).timeout(timeout);
  }

  Map<String, Object?> _buildMediaBody({
    required _GeneratedMediaKind kind,
    required String modelId,
    required String prompt,
    required AiCreationOptions options,
    required AiProtocolType protocol,
  }) {
    return switch (kind) {
      _GeneratedMediaKind.image => _buildImageBody(
        modelId: modelId,
        prompt: prompt,
        options: options,
        protocol: protocol,
      ),
      _GeneratedMediaKind.video => _buildVideoBody(
        modelId: modelId,
        prompt: prompt,
        options: options,
        protocol: protocol,
      ),
      _GeneratedMediaKind.audio => _buildAudioBody(
        modelId: modelId,
        prompt: prompt,
        options: options,
        protocol: protocol,
      ),
    };
  }

  Map<String, Object?> _buildImageBody({
    required String modelId,
    required String prompt,
    required AiCreationOptions options,
    required AiProtocolType protocol,
  }) {
    final body = <String, Object?>{
      'model': modelId,
      'prompt': prompt,
      'n': options.count > 0 ? options.count : 1,
      'response_format': 'b64_json',
    };
    // Size: canonical OpenAI format (`1024x1024`). When the user specifies an
    // aspect ratio instead, translate it to a concrete size for providers
    // that only accept `size`.
    final size = options.size ?? _sizeFromAspectRatio(options.aspectRatio);
    if (size != null) body['size'] = size;
    if (options.aspectRatio != null) {
      // Qwen/Grok/Seed accept `aspect_ratio`; harmless for others that ignore.
      body['aspect_ratio'] = options.aspectRatio;
    }
    if (options.quality != null) body['quality'] = options.quality;
    if (options.style != null) body['style'] = options.style;
    return body;
  }

  Map<String, Object?> _buildVideoBody({
    required String modelId,
    required String prompt,
    required AiCreationOptions options,
    required AiProtocolType protocol,
  }) {
    // Per-provider body shapes — many vendors deliberately do NOT speak the
    // OpenAI `prompt + n + response_format` schema. Sending the canonical
    // shape to providers like Sora 2 / MiniMax / DashScope yields silent
    // 400/422 errors that surface as “视频生成失败” in the UI.
    switch (protocol) {
      case AiProtocolType.openai:
        // OpenAI Sora 2: `{model, prompt, seconds, size}` (no `n`).
        final body = <String, Object?>{'model': modelId, 'prompt': prompt};
        final size =
            options.size ?? _videoSizeFromAspectRatio(options.aspectRatio);
        if (size != null) body['size'] = size;
        if (options.durationSeconds != null) {
          body['seconds'] = options.durationSeconds;
        }
        return body;
      case AiProtocolType.minimax:
        // MiniMax `/v1/video_generation`:
        //   `{model, prompt, prompt_optimizer}` — no `n`/`response_format`.
        return <String, Object?>{
          'model': modelId,
          'prompt': prompt,
          'prompt_optimizer': true,
        };
      case AiProtocolType.qwen:
        // DashScope native shape (works through compatible-mode passthrough):
        //   `{model, input:{prompt}, parameters:{size, duration}}`.
        final parameters = <String, Object?>{};
        final size =
            options.size ?? _videoSizeFromAspectRatio(options.aspectRatio);
        if (size != null) parameters['size'] = size;
        if (options.durationSeconds != null) {
          parameters['duration'] = options.durationSeconds;
        }
        return <String, Object?>{
          'model': modelId,
          'input': <String, Object?>{'prompt': prompt},
          if (parameters.isNotEmpty) 'parameters': parameters,
        };
      case AiProtocolType.grok:
        // grok2api `POST /v1/videos` (multipart):
        //   `{model, prompt, seconds, size, resolution_name, preset}`.
        // Reference: https://github.com/chenyme/grok2api/blob/main/README.md
        final body = <String, Object?>{'model': modelId, 'prompt': prompt};
        final size =
            options.size ?? _videoSizeFromAspectRatio(options.aspectRatio);
        if (size != null) body['size'] = size;
        if (options.durationSeconds != null) {
          body['seconds'] = options.durationSeconds;
        }
        // grok2api documents resolution_name (480p|720p) and preset
        // (fun|normal|spicy|custom) — surface via quality/style if set.
        if (options.quality != null) {
          body['resolution_name'] = options.quality;
        }
        if (options.style != null) {
          body['preset'] = options.style;
        }
        return body;
      case AiProtocolType.glm:
      case AiProtocolType.seed:
      case AiProtocolType.hunyuan:
      case AiProtocolType.stepfun:
      case AiProtocolType.wenxin:
      case AiProtocolType.gemini:
      case AiProtocolType.claude:
      case AiProtocolType.deepseek:
      case AiProtocolType.kimi:
      case AiProtocolType.ollama:
      case AiProtocolType.vllm:
      case AiProtocolType.sglang:
      case AiProtocolType.longcat:
      case AiProtocolType.joycode:
      case AiProtocolType.meta:
      case AiProtocolType.mimo:
        // GLM CogVideoX-style: `{model, prompt, quality, size, duration,
        // fps, with_audio}` — extra fields are tolerated by other providers
        // that ignore unknown keys (Seed/Doubao Seedance, custom OpenAI-
        // compat gateways).
        final body = <String, Object?>{
          'model': modelId,
          'prompt': prompt,
          'response_format': 'url',
        };
        if (options.aspectRatio != null) {
          body['aspect_ratio'] = options.aspectRatio;
        }
        final size =
            options.size ?? _videoSizeFromAspectRatio(options.aspectRatio);
        if (size != null) body['size'] = size;
        if (options.durationSeconds != null) {
          body['duration'] = options.durationSeconds;
          body['duration_seconds'] = options.durationSeconds;
        }
        if (options.quality != null) body['quality'] = options.quality;
        if (options.style != null) body['style'] = options.style;
        return body;
    }
  }

  /// Maps an aspect ratio to a concrete `WxH` video size for providers that
  /// only accept absolute resolutions (OpenAI Sora, DashScope wan).
  String? _videoSizeFromAspectRatio(String? ratio) {
    if (ratio == null) return null;
    switch (ratio.trim()) {
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

  Map<String, Object?> _buildAudioBody({
    required String modelId,
    required String prompt,
    required AiCreationOptions options,
    required AiProtocolType protocol,
  }) {
    final voice = options.style?.trim().isNotEmpty == true
        ? options.style!.trim()
        : null;
    switch (protocol) {
      case AiProtocolType.openai:
      case AiProtocolType.glm:
        // OpenAI TTS / GLM CogTTS share `/v1/audio/speech` body:
        //   `{model, input, voice, response_format}`.
        return <String, Object?>{
          'model': modelId,
          'input': prompt,
          'voice': voice ?? 'alloy',
          'response_format': 'mp3',
        };
      case AiProtocolType.qwen:
        // Qwen Qwen3-TTS / cosyvoice via DashScope native shape:
        //   `{model, input:{text}, parameters:{voice, format}}`.
        return <String, Object?>{
          'model': modelId,
          'input': <String, Object?>{'text': prompt},
          'parameters': <String, Object?>{
            if (voice != null) 'voice': voice,
            'format': 'mp3',
          },
        };
      case AiProtocolType.minimax:
        // MiniMax T2A v2 (`/v1/t2a_v2`):
        //   `{model, text, voice_setting:{voice_id, speed, vol, pitch},
        //     audio_setting:{sample_rate, bitrate, format}}`.
        return <String, Object?>{
          'model': modelId,
          'text': prompt,
          'voice_setting': <String, Object?>{
            'voice_id': voice ?? 'female-shaonv',
            'speed': 1.0,
            'vol': 1.0,
            'pitch': 0,
          },
          'audio_setting': <String, Object?>{
            'sample_rate': 32000,
            'bitrate': 128000,
            'format': 'mp3',
          },
        };
      case AiProtocolType.seed:
      case AiProtocolType.stepfun:
      case AiProtocolType.wenxin:
      case AiProtocolType.hunyuan:
      case AiProtocolType.gemini:
      case AiProtocolType.claude:
      case AiProtocolType.deepseek:
      case AiProtocolType.kimi:
      case AiProtocolType.grok:
      case AiProtocolType.ollama:
      case AiProtocolType.vllm:
      case AiProtocolType.sglang:
      case AiProtocolType.longcat:
      case AiProtocolType.joycode:
      case AiProtocolType.meta:
      case AiProtocolType.mimo:
        // Generic OpenAI-compatible fallback for custom gateways. Listed
        // protocols are already gated off in `supportsAudioGeneration` and
        // will fail-fast at the chat layer; this body is only reached for
        // user-overridden compatible models.
        return <String, Object?>{
          'model': modelId,
          'input': prompt,
          'voice': voice ?? 'alloy',
          'response_format': 'mp3',
        };
    }
  }

  String? _sizeFromAspectRatio(String? ratio) {
    if (ratio == null) return null;
    switch (ratio.trim()) {
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

  Map<String, Object?> _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) return decoded;
    } catch (error, stack) {
      silentLog(
        'ai_image_generation_service',
        'decode response body',
        error,
        stack,
      );
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
        'decode ${kind.storageValue} response body',
        error,
        stack,
      );
    }
    throw AiMediaGenerationException(
      '${kind.displayName} endpoint returned a non-JSON response.',
      rawResponseBody: body,
    );
  }

  /// Parses an OpenAI-compatible `{ data: [ { url | b64_json } ] }` payload
  /// and persists the returned bytes as markdown-ready image references.
  Future<String> _buildMarkdownFromResponse({
    required Map<String, Object?> decoded,
    required String altText,
  }) async {
    final raw = decoded['data'];
    if (raw is! List || raw.isEmpty) return '';
    final buffer = StringBuffer();
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = entry.cast<String, Object?>();
      // Some providers (DALL·E, Qwen) return a `revised_prompt` that is
      // more descriptive than the original. Prefer it for alt text when
      // available, but fall back to the caller-supplied text.
      final revisedPrompt = '${map['revised_prompt'] ?? ''}'.trim();
      final effectiveAlt = revisedPrompt.isNotEmpty ? revisedPrompt : altText;
      final b64 = '${map['b64_json'] ?? ''}'.trim();
      if (b64.isNotEmpty) {
        final md = await saveInlineMediaToMarkdown(
          AiInlineMedia(mimeType: 'image/png', base64Data: b64),
          label: effectiveAlt,
        );
        if (md.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.writeln();
          buffer.write(md);
        }
        continue;
      }
      final url = '${map['url'] ?? ''}'.trim();
      if (url.isNotEmpty) {
        final bytes = await _downloadBytes(url);
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
        // Fall back to rendering the direct URL if download failed.
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
  }) async {
    if (kind.isImage) {
      return _buildMarkdownFromResponse(decoded: decoded, altText: label);
    }
    final entries = _extractMediaEntries(decoded, kind);
    if (entries.isEmpty) return '';
    final buffer = StringBuffer();
    for (final entry in entries) {
      final effectiveLabel = sanitizeMarkdownAltText(
        entry.label?.trim().isNotEmpty == true ? entry.label! : label,
      );
      final base64Data = entry.base64Data?.trim();
      if (base64Data != null && base64Data.isNotEmpty) {
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
      final url = entry.url?.trim();
      if (url != null && url.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.writeln();
        buffer.write('[$effectiveLabel]($url)');
      }
    }
    return buffer.toString();
  }

  List<_MediaPayloadEntry> _extractMediaEntries(
    Map<String, Object?> decoded,
    _GeneratedMediaKind kind,
  ) {
    final entries = <_MediaPayloadEntry>[];

    void collect(Object? value, {String? label, String? mimeType}) {
      if (value == null) return;
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return;
        if (_looksLikeUrl(trimmed) || trimmed.startsWith('file:')) {
          entries.add(
            _MediaPayloadEntry(url: trimmed, label: label, mimeType: mimeType),
          );
        } else if (_looksLikeBase64(trimmed)) {
          entries.add(
            _MediaPayloadEntry(
              base64Data: trimmed,
              label: label,
              mimeType: mimeType,
            ),
          );
        }
        return;
      }
      if (value is List) {
        for (final item in value) {
          collect(item, label: label, mimeType: mimeType);
        }
        return;
      }
      if (value is! Map) return;
      final map = Map<String, Object?>.from(value);
      final nestedLabel = _firstTextValue(map, const <String>[
        'revised_prompt',
        'prompt',
        'caption',
        'transcript',
        'name',
        'title',
      ])?.trim();
      final nextLabel = nestedLabel?.isNotEmpty == true ? nestedLabel : label;
      final nextMimeType = _firstTextValue(map, const <String>[
        'mime_type',
        'mimeType',
        'content_type',
        'contentType',
        'media_type',
        'mediaType',
      ])?.trim();
      final effectiveMimeType = nextMimeType?.isNotEmpty == true
          ? nextMimeType
          : mimeType;

      for (final key in _urlKeysFor(kind)) {
        final candidate = map[key];
        if (candidate is String && candidate.trim().isNotEmpty) {
          collect(candidate, label: nextLabel, mimeType: effectiveMimeType);
        }
      }
      for (final key in _base64KeysFor(kind)) {
        final candidate = map[key];
        if (candidate is String && candidate.trim().isNotEmpty) {
          collect(candidate, label: nextLabel, mimeType: effectiveMimeType);
        }
      }
      for (final key in const <String>[
        'data',
        'output',
        'result',
        'results',
        'content',
        'media',
        'file',
        'files',
        // GLM CogVideoX returns the playable URL inside a `video_result` array.
        'video_result',
        'videoResult',
        'audio_result',
        'audioResult',
        'image_result',
        'imageResult',
      ]) {
        final nested = map[key];
        if (nested == null || identical(nested, value)) continue;
        collect(nested, label: nextLabel, mimeType: effectiveMimeType);
      }
    }

    collect(decoded);
    final seen = <String>{};
    return entries
        .where((entry) {
          final key = entry.url ?? entry.base64Data ?? '';
          if (key.isEmpty || seen.contains(key)) return false;
          seen.add(key);
          return true;
        })
        .toList(growable: false);
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

  String? _firstTextValue(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  bool _looksLikeUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'file');
  }

  bool _looksLikeBase64(String value) {
    final normalized = value.trim();
    if (normalized.length < 32) return false;
    return RegExp(r'^[A-Za-z0-9+/=\r\n]+$').hasMatch(normalized);
  }

  Future<_PolledMediaResult> _pollMediaOperation({
    required String initialUrl,
    required Map<String, Object?> initialPayload,
    required _GeneratedMediaKind kind,
    required String label,
    required AiProtocolType protocol,
    required Map<String, String> requestHeaders,
    required Duration timeout,
    required DateTime startedAt,
  }) async {
    final operationUrl = _resolveOperationUrl(
      initialUrl,
      initialPayload,
      protocol,
    );
    if (operationUrl == null) {
      return const _PolledMediaResult.empty();
    }
    final deadline = startedAt.add(timeout);
    var lastBody = jsonEncode(initialPayload);
    var attempt = 0;
    var transientFailures = 0;
    while (DateTime.now().toUtc().isBefore(deadline)) {
      attempt += 1;
      final remaining = deadline.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero) break;
      // Add bounded jitter to spread parallel pollers and avoid synchronized
      // hammering against rate-limited async-task endpoints. Long-running
      // video tasks (e.g. grok-imagine-video) routinely exceed several
      // minutes, so cap the per-iteration backoff at 5s after a warm-up
      // window rather than imposing a hard attempt cap that would expire
      // well before the deadline.
      final int baseMs;
      if (attempt < 6) {
        baseMs = 1500;
      } else if (attempt < 16) {
        baseMs = 3000;
      } else {
        baseMs = 5000;
      }
      final jitterMs = _pollJitter.nextInt(400) - 200;
      final wait = Duration(milliseconds: math.max(250, baseMs + jitterMs));
      if (wait < remaining) {
        await Future<void>.delayed(wait);
      }
      final requestRemaining = deadline.difference(DateTime.now().toUtc());
      // Guard against `.timeout(near-zero)` which would instantly throw
      // TimeoutException after sub-millisecond delays. If we have less
      // than a second of budget left there is no point firing another
      // request — exit and let the caller surface the deadline.
      if (requestRemaining < const Duration(seconds: 1)) break;
      final effectiveTimeout = requestRemaining < const Duration(seconds: 15)
          ? requestRemaining
          : const Duration(seconds: 15);
      final pollingHeaders = Map<String, String>.from(requestHeaders)
        ..['accept'] = 'application/json';
      final response = await _client
          .get(Uri.parse(operationUrl), headers: pollingHeaders)
          .timeout(effectiveTimeout);
      lastBody = response.body;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (_isTransientPollStatus(response.statusCode) &&
            transientFailures < 4) {
          transientFailures += 1;
          final retryAfter = _parseRetryAfter(response.headers['retry-after']);
          final backoffMs = math.min(
            8000,
            1500 * (1 << math.min(transientFailures - 1, 3)),
          );
          final backoff =
              retryAfter ??
              Duration(milliseconds: backoffMs + _pollJitter.nextInt(400));
          final budget = deadline.difference(DateTime.now().toUtc());
          if (backoff < budget) {
            await Future<void>.delayed(backoff);
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
      // MiniMax video task: status==Success carries `file_id` instead of a
      // direct URL. Resolve via /files/retrieve before returning.
      if (protocol == AiProtocolType.minimax && kind.isVideo) {
        final status = _operationStatus(decoded);
        if (status == 'success') {
          final fileId = _findFirstString(decoded, const <String>[
            'file_id',
            'fileId',
          ])?.trim();
          if (fileId != null && fileId.isNotEmpty) {
            final downloadUrl = await _resolveMiniMaxFileUrl(
              initialUrl: initialUrl,
              fileId: fileId,
              requestHeaders: requestHeaders,
              effectiveTimeout: effectiveTimeout,
            );
            if (downloadUrl != null && downloadUrl.isNotEmpty) {
              final safeLabel = sanitizeMarkdownAltText(label);
              return _PolledMediaResult(
                markdown: '[$safeLabel]($downloadUrl)',
                rawResponseBody: response.body,
              );
            }
          }
        }
      }
      final markdown = await _buildMarkdownFromMediaResponse(
        decoded: decoded,
        kind: kind,
        label: label,
      );
      if (markdown.isNotEmpty) {
        return _PolledMediaResult(
          markdown: markdown,
          rawResponseBody: response.body,
        );
      }
      final status = _operationStatus(decoded);
      // OpenAI Sora 2 and grok2api expose the finished mp4 only through
      // `GET /v1/videos/{id}/content` (binary) — the polling JSON has no
      // url/b64 field. When the task reports completion, fetch the content
      // with the provider's auth headers and persist it locally.
      if (kind.isVideo &&
          (protocol == AiProtocolType.openai ||
              protocol == AiProtocolType.grok) &&
          _isTerminalSuccessStatus(status)) {
        final contentMarkdown = await _downloadSoraStyleVideoContent(
          operationUrl: operationUrl,
          requestHeaders: requestHeaders,
          effectiveTimeout: effectiveTimeout,
          label: label,
        );
        if (contentMarkdown.isNotEmpty) {
          return _PolledMediaResult(
            markdown: contentMarkdown,
            rawResponseBody: response.body,
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
    return _PolledMediaResult(markdown: '', rawResponseBody: lastBody);
  }

  /// Sora 2 / grok2api expose the rendered mp4 only as a binary stream at
  /// `{operationUrl}/content`. Fetches it with the provider's auth headers
  /// and saves it locally so the downstream UI can play it via a `file://`
  /// link without the user re-authenticating.
  Future<String> _downloadSoraStyleVideoContent({
    required String operationUrl,
    required Map<String, String> requestHeaders,
    required Duration effectiveTimeout,
    required String label,
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
    // Allow a slightly larger budget for the binary download since the
    // polling timeout is intentionally short.
    final downloadTimeout = effectiveTimeout < const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : effectiveTimeout;
    final response = await _client
        .get(contentUri, headers: downloadHeaders)
        .timeout(downloadTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiMediaGenerationException(
        _MediaErrorMessages.httpStatus(
          _GeneratedMediaKind.video,
          response.statusCode,
          serverMessage: _extractError(response.body),
          contextHint: 'GET /content',
        ),
        rawResponseBody: response.body,
      );
    }
    if (response.bodyBytes.isEmpty) return '';
    final mimeType = _responseContentType(response.headers);
    final effectiveMime = mimeType.startsWith('video/')
        ? mimeType
        : 'video/mp4';
    return _saveBinaryMediaBytes(
      kind: _GeneratedMediaKind.video,
      bytes: response.bodyBytes,
      mimeType: effectiveMime,
      label: label,
    );
  }

  /// MiniMax video pipeline emits a `file_id` once the task completes; the
  /// playable mp4 lives behind a separate `/v1/files/retrieve` lookup.
  Future<String?> _resolveMiniMaxFileUrl({
    required String initialUrl,
    required String fileId,
    required Map<String, String> requestHeaders,
    required Duration effectiveTimeout,
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
      ..['accept'] = 'application/json';
    http.Response? response;
    for (var i = 0; i < 2; i++) {
      response = await _client
          .get(retrieveUri, headers: pollingHeaders)
          .timeout(effectiveTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) break;
      if (!_isTransientPollStatus(response.statusCode) || i == 1) {
        return null;
      }
      // Single retry with jitter to absorb a brief 5xx/429 without
      // dropping a successful video task on the floor.
      final retryAfter = _parseRetryAfter(response.headers['retry-after']);
      await Future<void>.delayed(
        retryAfter ?? Duration(milliseconds: 750 + _pollJitter.nextInt(400)),
      );
    }
    if (response == null ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      return null;
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, Object?>) {
        final url = _findFirstString(decoded, const <String>[
          'download_url',
          'downloadUrl',
          'backup_download_url',
          'file_url',
          'fileUrl',
          'url',
        ]);
        return url?.trim();
      }
    } catch (error, stack) {
      silentLog(
        'ai_image_generation_service',
        'parse minimax /files/retrieve',
        error,
        stack,
      );
    }
    return null;
  }

  /// Status codes that warrant a brief backoff retry instead of failing the
  /// whole media task. Cloud LLM media APIs commonly emit 429 (rate limit) or
  /// 5xx during async-task polling without the task itself being dead.
  static const Set<int> _transientPollStatuses = <int>{
    408,
    425,
    429,
    500,
    502,
    503,
    504,
  };

  bool _isTransientPollStatus(int status) =>
      _transientPollStatuses.contains(status);

  static final math.Random _pollJitter = math.Random();

  /// Parses an HTTP `Retry-After` header (seconds or HTTP-date) to a Duration.
  /// Returns null when the value is missing/invalid so callers can fall back
  /// to local exponential backoff.
  static Duration? _parseRetryAfter(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final seconds = int.tryParse(trimmed);
    if (seconds != null && seconds >= 0) {
      // Cap at 30s so a hostile/misconfigured server cannot block the
      // media task for the full deadline window.
      return Duration(seconds: math.min(seconds, 30));
    }
    try {
      final when = HttpDate.parse(trimmed);
      final delta = when.toUtc().difference(DateTime.now().toUtc());
      if (delta.isNegative) return Duration.zero;
      if (delta > const Duration(seconds: 30)) {
        return const Duration(seconds: 30);
      }
      return delta;
    } catch (_) {
      return null;
    }
  }

  String? _resolveOperationUrl(
    String initialUrl,
    Map<String, Object?> payload,
    AiProtocolType protocol,
  ) {
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
    if (explicitUrl != null && explicitUrl.trim().isNotEmpty) {
      final trimmedUrl = explicitUrl.trim();
      final parsed = Uri.tryParse(trimmedUrl);
      if (parsed != null && parsed.hasScheme) {
        return trimmedUrl;
      }
      return Uri.parse(initialUrl).resolve(trimmedUrl).toString();
    }
    final id = _findFirstString(payload, const <String>[
      'id',
      'task_id',
      'taskId',
      'job_id',
      'jobId',
      'operation_id',
      'operationId',
    ])?.trim();
    if (id == null || id.isEmpty) return null;
    final uri = Uri.parse(initialUrl);
    return switch (protocol) {
      // GLM CogVideoX: status lives under `/api/paas/v4/async-result/{id}`.
      AiProtocolType.glm => () {
        final segments = uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .toList(growable: true);
        // Strip trailing `videos/generations` (or any sibling kind) and
        // append `async-result/{id}`.
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
      // MiniMax: GET /v1/query/video_generation?task_id={id}.
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
      // Qwen DashScope native task lookup: GET /api/v1/tasks/{id}.
      // We can't always rebuild that path from a `/compatible-mode/...` URL
      // safely, so fall back to default path-append behaviour and let the
      // gateway redirect when needed.
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
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }
    for (final value in map.values) {
      if (value is Map) {
        final nested = _findFirstString(Map<String, Object?>.from(value), keys);
        if (nested != null) return nested;
      }
    }
    return null;
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
    return (status ?? '').trim().toLowerCase();
  }

  bool _isTerminalFailureStatus(String status) {
    return status == 'failed' ||
        status == 'failure' ||
        status == 'error' ||
        status == 'cancelled' ||
        status == 'canceled';
  }

  /// Sora 2 reports `completed`; grok2api may also report `succeeded`/`done`.
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
        mimeType: mimeType.trim().isNotEmpty ? mimeType : _defaultMimeFor(kind),
        base64Data: base64Encode(bytes),
      ),
      label: label,
    );
  }

  String _responseContentType(Map<String, String> headers) {
    final raw = headers['content-type'] ?? headers['Content-Type'] ?? '';
    return raw.split(';').first.trim().toLowerCase();
  }

  bool _isBinaryMediaContentType(String contentType, _GeneratedMediaKind kind) {
    if (contentType.isEmpty || _jsonContentTypes.contains(contentType)) {
      return false;
    }
    if (kind.isVideo) return contentType.startsWith('video/');
    if (kind.isAudio) return contentType.startsWith('audio/');
    if (kind.isImage) return contentType.startsWith('image/');
    return false;
  }

  String _defaultMimeFor(_GeneratedMediaKind kind) {
    return switch (kind) {
      _GeneratedMediaKind.image => 'image/png',
      _GeneratedMediaKind.video => 'video/mp4',
      _GeneratedMediaKind.audio => 'audio/mpeg',
    };
  }

  Future<List<int>?> _downloadBytes(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
    } catch (error, stack) {
      silentLog(
        'ai_image_generation_service',
        'fetch remote image bytes',
        error,
        stack,
      );
    }
    return null;
  }

  String _mimeFromUrl(String url) {
    // Parse the URL path to avoid false positives from query parameters
    // or unrelated path segments (e.g. "image.png.backup?format=webp").
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.gif')) return 'image/gif';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    return 'image/png';
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) return error.trim();
        if (error is Map<String, Object?>) {
          final message = '${error['message'] ?? ''}'.trim();
          if (message.isNotEmpty) return message;
        }
        final message = '${decoded['message'] ?? ''}'.trim();
        if (message.isNotEmpty) return message;
      }
    } catch (error, stack) {
      silentLog(
        'ai_image_generation_service',
        'decode error response body',
        error,
        stack,
      );
    }
    return body.trim().isEmpty ? 'Unknown error' : body.trim();
  }

  void dispose() {
    _client.close();
  }
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
  });

  const _PolledMediaResult.empty() : markdown = '', rawResponseBody = '';

  final String markdown;
  final String rawResponseBody;
}

/// 集中收敛图像 / 视频 / 音频生成阶段的错误文案，与
/// `AiChatService._ChatErrorMessages`、`AiModelScanner._ScanErrorMessages`
/// 保持一致的「现象 / 原因 / 建议」三段式中英双语风格。文案中会带上
/// 媒体类型 (image / video / audio)，便于用户直观判断哪一条流水线失败。
/// Thin shim around [AiTransportDiagnosticMessages] that injects the media
/// kind label into the title suffix (e.g. `[Image (image)]`).
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

  static String timeout(_GeneratedMediaKind kind, Duration limit) =>
      AiTransportDiagnosticMessages.timeout(limit, contextLabel: _label(kind));

  static String httpStatus(
    _GeneratedMediaKind kind,
    int code, {
    String serverMessage = '',
    String contextHint = '',
  }) =>
      AiTransportDiagnosticMessages.httpStatus(
        code,
        serverMessage: serverMessage,
        contextLabel: _label(kind),
        contextHint: contextHint,
      );
}
