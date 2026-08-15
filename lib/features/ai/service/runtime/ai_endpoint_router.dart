import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_endpoint_override.dart';
import '../../model/ai_model_config.dart';

const String _defaultEndpointMethod = 'POST';
const String _defaultEndpointTransport = 'json';
final RegExp _apiVersionSegmentPattern = RegExp(r'^v[0-9]+(beta|alpha)?$');

class AiResolvedEndpoint {
  const AiResolvedEndpoint({
    required this.url,
    required this.method,
    required this.transport,
    this.headers = const <String, String>{},
    this.queryDefaults = const <String, String>{},
  });

  final String url;
  final String method;
  final String transport;
  final Map<String, String> headers;
  final Map<String, String> queryDefaults;
}

class AiEndpointRouter {
  const AiEndpointRouter();

  /// Resolves a fixed provider-native path while still applying the same base
  /// URL cleanup, API-version overlap handling, and model placeholders as the
  /// normal family router. Endpoint overrides are intentionally ignored: a
  /// native operation such as MiniMax voice cloning must not accidentally
  /// inherit the provider's unrelated generic `/audio/speech` override.
  AiResolvedEndpoint resolveProviderPath(
    AiModelConfig config,
    AiApiFamily family, {
    required String path,
    String method = _defaultEndpointMethod,
    String transport = _defaultEndpointTransport,
  }) {
    return AiResolvedEndpoint(
      url: _resolveUrl(
        config.normalizedBaseUrl,
        config,
        family,
        null,
        fallbackPath: path,
      ),
      method: (nullIfBlank(method) ?? _defaultEndpointMethod).toUpperCase(),
      transport: lowercaseStringFromValue(
        transport,
        fallback: _defaultEndpointTransport,
      ),
    );
  }

  AiResolvedEndpoint resolve(
    AiModelConfig config,
    AiApiFamily family, {
    String? fallbackPath,
    String method = _defaultEndpointMethod,
    String transport = _defaultEndpointTransport,
  }) {
    final override = config.endpointOverrides[family];
    final fallbackMethod = nullIfBlank(method) ?? _defaultEndpointMethod;
    final fallbackTransport =
        nullIfBlank(transport) ?? _defaultEndpointTransport;
    final resolvedMethod = (nullIfBlank(override?.method) ?? fallbackMethod)
        .toUpperCase();
    final resolvedTransport = lowercaseStringFromValue(
      override?.transport,
      fallback: fallbackTransport,
    );
    final url = _resolveUrl(
      config.normalizedBaseUrl,
      config,
      family,
      override,
      fallbackPath: fallbackPath,
    );
    return AiResolvedEndpoint(
      url: url,
      method: resolvedMethod,
      transport: resolvedTransport,
      headers: override?.headers ?? const <String, String>{},
      queryDefaults: override?.queryDefaults ?? const <String, String>{},
    );
  }

  String _resolveUrl(
    String baseUrl,
    AiModelConfig config,
    AiApiFamily family,
    AiEndpointOverride? override, {
    String? fallbackPath,
  }) {
    final queryDefaults = override?.queryDefaults ?? const <String, String>{};
    final explicitUrl = nullIfBlank(override?.url);
    if (explicitUrl != null) {
      final explicitUri = Uri.parse(
        _replaceModelPlaceholders(explicitUrl, config, family),
      );
      final mergedQuery = <String, String>{
        ...queryDefaults,
        ...explicitUri.queryParameters,
      };
      return explicitUri
          .replace(queryParameters: mergedQuery.isEmpty ? null : mergedQuery)
          .toString();
    }
    final overridePath = nullIfBlank(override?.path);
    final usesExplicitOverridePath = overridePath != null;
    final rawPath = usesExplicitOverridePath
        ? overridePath
        : nullIfBlank(fallbackPath) ?? _defaultPathFor(family);
    final pathParts = rawPath.split('?');
    final path = usesExplicitOverridePath
        ? pathParts.first
        : _normalizeDefaultPathForCompletionMode(
            pathParts.first,
            autoCompleteBaseUrl: config.autoCompleteBaseUrl,
          );
    final pathQuery = pathParts.length > 1
        ? pathParts.sublist(1).join('&')
        : '';
    if (path.isEmpty) return baseUrl;
    final baseUri = Uri.parse(baseUrl);
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final baseSegments = _baseSegmentsForEndpoint(
      baseUri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false),
    );
    var pathSegments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map((segment) => _replaceModelPlaceholders(segment, config, family))
        .toList(growable: false);
    if (baseSegments.isNotEmpty &&
        pathSegments.isNotEmpty &&
        baseSegments.last.toLowerCase() == pathSegments.first.toLowerCase() &&
        _isApiVersionSegment(baseSegments.last.toLowerCase()) &&
        _isApiVersionSegment(pathSegments.first.toLowerCase())) {
      pathSegments = pathSegments.skip(1).toList(growable: false);
    }
    final overlapLength = _leadingPathOverlap(baseSegments, pathSegments);
    final mergedPathSegments = <String>[
      ...baseSegments,
      ...pathSegments.skip(overlapLength),
    ];
    final mergedQuery = <String, String>{
      ...queryDefaults,
      ...baseUri.queryParameters,
      ...Uri.splitQueryString(pathQuery),
    };
    return baseUri
        .replace(
          pathSegments: mergedPathSegments,
          queryParameters: mergedQuery.isEmpty ? null : mergedQuery,
        )
        .toString();
  }

  String _defaultPathFor(AiApiFamily family) {
    return switch (family) {
      AiApiFamily.responses => 'v1/responses',
      AiApiFamily.chatCompletions => 'v1/chat/completions',
      AiApiFamily.completions => 'v1/completions',
      AiApiFamily.embeddings => 'v1/embeddings',
      AiApiFamily.moderations => 'v1/moderations',
      AiApiFamily.rerank => 'v1/rerank',
      AiApiFamily.models => 'v1/models',
      AiApiFamily.imageGeneration => 'v1/images/generations',
      AiApiFamily.imageEdit => 'v1/images/edits',
      AiApiFamily.audioSpeech => 'v1/audio/speech',
      AiApiFamily.audioTranscription => 'v1/audio/transcriptions',
      AiApiFamily.audioTranslation => 'v1/audio/translations',
      AiApiFamily.videoGeneration => 'v1/videos',
      AiApiFamily.realtime => 'v1/realtime',
      AiApiFamily.files => 'v1/files',
      AiApiFamily.fineTunes => 'v1/fine-tunes',
      AiApiFamily.vectorStores => 'v1/vector_stores',
      AiApiFamily.vectorStoreFiles =>
        'v1/vector_stores/{vector_store_id}/files',
      AiApiFamily.tokenCount => 'v1/token/count',
      AiApiFamily.search => 'v1/search',
      AiApiFamily.audioVoices => 'v1/audio/voices',
      AiApiFamily.audioSystemVoices => 'v1/audio/system_voices',
      AiApiFamily.audioVoicePreview => 'v1/audio/voices/preview',
      AiApiFamily.audioAsr => 'v1/audio/asr/file/submit',
      AiApiFamily.audioAsrSse => 'v1/audio/asr/sse',
      AiApiFamily.messages => 'v1/messages',
    };
  }

  String _normalizeDefaultPathForCompletionMode(
    String path, {
    required bool autoCompleteBaseUrl,
  }) {
    if (autoCompleteBaseUrl) return path;
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final segments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty || !_isApiVersionSegment(segments.first)) {
      return path;
    }
    return segments.skip(1).join('/');
  }

  List<String> _baseSegmentsForEndpoint(List<String> segments) {
    if (segments.isEmpty) return segments;
    var current = segments;
    var changed = true;
    while (changed && current.isNotEmpty) {
      changed = false;
      if (_looksLikeGeminiModelAction(current)) {
        current = current.sublist(0, current.length - 2);
        changed = true;
        continue;
      }
      for (final suffix in _knownEndpointSuffixes) {
        if (_endsWithSegments(current, suffix)) {
          current = current.sublist(0, current.length - suffix.length);
          changed = true;
          break;
        }
      }
    }
    if (current.isEmpty && segments.isNotEmpty) {
      return _fallbackVersionBase(segments);
    }
    return current;
  }

  bool _looksLikeGeminiModelAction(List<String> segments) {
    if (segments.length < 2) return false;
    if (segments[segments.length - 2].toLowerCase() != 'models') {
      return false;
    }
    final last = segments.last.toLowerCase();
    return last.contains(':generatecontent') ||
        last.contains(':streamgeneratecontent') ||
        last.contains(':embedcontent') ||
        last.contains(':batchembedcontents');
  }

  List<String> _fallbackVersionBase(List<String> segments) {
    final versionIndex = segments.lastIndexWhere(
      (segment) => _isApiVersionSegment(segment.toLowerCase()),
    );
    if (versionIndex >= 0) {
      return segments.sublist(0, versionIndex + 1);
    }
    return const <String>[];
  }

  bool _endsWithSegments(List<String> value, List<String> suffix) {
    if (suffix.isEmpty || value.length < suffix.length) return false;
    final offset = value.length - suffix.length;
    for (var i = 0; i < suffix.length; i++) {
      if (value[offset + i].toLowerCase() != suffix[i].toLowerCase()) {
        return false;
      }
    }
    return true;
  }

  bool _isApiVersionSegment(String segment) {
    return segment == 'v1' ||
        segment == 'v2' ||
        segment == 'v3' ||
        segment == 'v4' ||
        _apiVersionSegmentPattern.hasMatch(segment);
  }

  String _replaceModelPlaceholders(
    String value,
    AiModelConfig config,
    AiApiFamily family,
  ) {
    final modelId = config.resolveOperationModelId(family);
    return value
        .replaceAll('{model_id}', modelId)
        .replaceAll('{model}', modelId);
  }

  /// 已知的端点后缀，用于从完整 URL 反推 base。
  ///
  /// 顺序敏感：匹配到第一条就 break，因此共享同一末段的多段后缀必须排在
  /// 单段版本之前，否则永远匹配不到。同一后缀也不要登记两次——重复项不可达。
  static const List<List<String>> _knownEndpointSuffixes = <List<String>>[
    <String>['chat', 'completions'],
    <String>['messages'],
    <String>['responses'],
    <String>['completions'],
    <String>['embeddings'],
    <String>['embedContent'],
    <String>['batchEmbedContents'],
    <String>['moderations'],
    <String>['rerank'],
    <String>['models'],
    <String>['images', 'generations'],
    <String>['images', 'edits'],
    <String>['images', 'generations:predict'],
    <String>['images', 'edits:predict'],
    <String>['audio', 'speech'],
    <String>['audio', 'transcriptions'],
    <String>['audio', 'translations'],
    <String>['contents', 'generations', 'tasks'],
    <String>['videos', 'generations'],
    <String>['videos'],
    <String>['query', 'video_generation'],
    <String>['video_generation'],
    <String>['realtime', 'sessions'],
    <String>['realtime'],
    <String>['files', 'retrieve'],
    <String>['files'],
    <String>['fine-tunes'],
    <String>['fine_tuning', 'jobs'],
    <String>['vector_stores'],
    <String>['token', 'count'],
    <String>['search'],
    <String>['audio', 'voices'],
    <String>['audio', 'system_voices'],
    <String>['audio', 'voices', 'preview'],
    <String>['audio', 'asr', 'file', 'submit'],
    <String>['audio', 'asr', 'file', 'query'],
    <String>['audio', 'asr', 'sse'],
    <String>['messages', 'count_tokens'],
  ];

  int _leadingPathOverlap(
    List<String> baseSegments,
    List<String> pathSegments,
  ) {
    final maxOverlap = baseSegments.length < pathSegments.length
        ? baseSegments.length
        : pathSegments.length;
    for (var length = maxOverlap; length > 0; length--) {
      final baseSuffix = baseSegments.skip(baseSegments.length - length);
      final pathPrefix = pathSegments.take(length);
      var matches = true;
      final baseIterator = baseSuffix.iterator;
      final pathIterator = pathPrefix.iterator;
      while (baseIterator.moveNext() && pathIterator.moveNext()) {
        if (baseIterator.current != pathIterator.current) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return length;
      }
    }
    return 0;
  }
}
