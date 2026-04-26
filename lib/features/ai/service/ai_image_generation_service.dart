import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../app/support/silent_log.dart';
import '../model/ai_creation_mode.dart';
import '../model/ai_model_catalog.dart';
import '../model/ai_model_config.dart';
import '../model/ai_token_usage.dart';
import 'ai_protocol_adapter.dart';

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
    : _client = client ?? http.Client();

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
      case AiProtocolType.hunyuan:
        return true;
      // Wenxin/StepFun lack a stable OpenAI-compatible video endpoint as of
      // 2026; routing them through `/v1/videos/generations` only ever yields
      // HTTP 404/405. Gate them off until a real adapter exists.
      case AiProtocolType.stepfun:
      case AiProtocolType.wenxin:
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
      case AiProtocolType.seed:
      case AiProtocolType.stepfun:
      case AiProtocolType.minimax:
      case AiProtocolType.hunyuan:
        return true;
      // Wenxin TTS is exposed through Baidu's bespoke API rather than an
      // OpenAI-compatible `/v1/audio/speech` endpoint, so default routing
      // would only return 404. Disable until a dedicated adapter lands.
      case AiProtocolType.wenxin:
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
      throw const AiMediaGenerationException('Image request timed out.');
    } on http.ClientException catch (error) {
      throw AiMediaGenerationException(error.message);
    } on SocketException catch (error) {
      throw AiMediaGenerationException('Network error: ${error.message}');
    } on TlsException catch (error) {
      throw AiMediaGenerationException('TLS error: ${error.message}');
    }
    final endedAt = DateTime.now().toUtc();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiMediaGenerationException(
        'HTTP ${response.statusCode}: ${_extractError(response.body)}',
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
    Duration timeout = const Duration(minutes: 5),
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
    final body = _buildMediaBody(
      kind: kind,
      modelId: modelId,
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
        '${kind.displayName} request timed out.',
      );
    } on http.ClientException catch (error) {
      throw AiMediaGenerationException(error.message);
    } on SocketException catch (error) {
      throw AiMediaGenerationException('Network error: ${error.message}');
    } on TlsException catch (error) {
      throw AiMediaGenerationException('TLS error: ${error.message}');
    }
    final endedAt = DateTime.now().toUtc();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiMediaGenerationException(
        'HTTP ${response.statusCode}: ${_extractError(response.body)}',
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
        AiProtocolType.minimax => const <String>['videos', 'generations'],
        _ => const <String>['videos', 'generations'],
      };
    }
    if (kind.isAudio) {
      return switch (protocol) {
        AiProtocolType.minimax => const <String>['audio', 'speech'],
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
  }) {
    final body = <String, Object?>{
      'model': modelId,
      'prompt': prompt,
      'n': options.count > 0 ? options.count : 1,
      'response_format': 'url',
    };
    if (options.aspectRatio != null) {
      body['aspect_ratio'] = options.aspectRatio;
    }
    if (options.size != null) body['size'] = options.size;
    if (options.durationSeconds != null) {
      body['duration'] = options.durationSeconds;
      body['duration_seconds'] = options.durationSeconds;
    }
    if (options.quality != null) body['quality'] = options.quality;
    if (options.style != null) body['style'] = options.style;
    return body;
  }

  Map<String, Object?> _buildAudioBody({
    required String modelId,
    required String prompt,
    required AiCreationOptions options,
    required AiProtocolType protocol,
  }) {
    if (protocol == AiProtocolType.openai) {
      return <String, Object?>{
        'model': modelId,
        'input': prompt,
        'voice': options.style?.trim().isNotEmpty == true
            ? options.style!.trim()
            : 'alloy',
        'response_format': 'mp3',
      };
    }
    final body = <String, Object?>{
      'model': modelId,
      'prompt': prompt,
      'input': prompt,
      'text': prompt,
      'n': options.count > 0 ? options.count : 1,
      'response_format': 'mp3',
    };
    if (options.durationSeconds != null) {
      body['duration'] = options.durationSeconds;
      body['duration_seconds'] = options.durationSeconds;
    }
    if (options.quality != null) body['quality'] = options.quality;
    if (options.style != null) body['voice'] = options.style;
    return body;
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
    required Map<String, String> requestHeaders,
    required Duration timeout,
    required DateTime startedAt,
  }) async {
    final operationUrl = _resolveOperationUrl(initialUrl, initialPayload);
    if (operationUrl == null) {
      return const _PolledMediaResult.empty();
    }
    final deadline = startedAt.add(timeout);
    var lastBody = jsonEncode(initialPayload);
    var attempt = 0;
    while (attempt < 90 && DateTime.now().toUtc().isBefore(deadline)) {
      attempt += 1;
      final remaining = deadline.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero) break;
      final wait = Duration(milliseconds: attempt < 6 ? 1200 : 2500);
      if (wait < remaining) {
        await Future<void>.delayed(wait);
      }
      final requestRemaining = deadline.difference(DateTime.now().toUtc());
      if (requestRemaining <= Duration.zero) break;
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
        throw AiMediaGenerationException(
          'HTTP ${response.statusCode}: ${_extractError(response.body)}',
          rawResponseBody: response.body,
        );
      }
      final decoded = _decodeJsonForKind(response.body, kind);
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
      if (_isTerminalFailureStatus(status)) {
        throw AiMediaGenerationException(
          '${kind.displayName} generation failed: ${_extractError(response.body)}',
          rawResponseBody: response.body,
        );
      }
    }
    return _PolledMediaResult(markdown: '', rawResponseBody: lastBody);
  }

  String? _resolveOperationUrl(
    String initialUrl,
    Map<String, Object?> payload,
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
    final segments =
        uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .toList(growable: true)
          ..add(id);
    return uri.replace(pathSegments: segments).toString();
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
