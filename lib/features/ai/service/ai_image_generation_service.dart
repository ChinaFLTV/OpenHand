import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../app/support/silent_log.dart';
import '../model/ai_creation_mode.dart';
import '../model/ai_model_config.dart';
import '../model/ai_token_usage.dart';
import 'ai_protocol_adapter.dart';

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

/// Service that routes image-generation (and eventually video/audio)
/// requests to the correct vendor endpoint.
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

  /// Returns the model id to use for image generation. The user is expected
  /// to configure an image-capable model directly in their provider settings.
  static String resolveImageModelId(AiModelConfig model, AiCreationMode mode) {
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
    if (!supportsImageGeneration(model.protocolType)) {
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
