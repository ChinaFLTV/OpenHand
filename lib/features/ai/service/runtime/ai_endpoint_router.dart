import '../../model/ai_api_family.dart';
import '../../model/ai_endpoint_override.dart';
import '../../model/ai_model_config.dart';

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

  AiResolvedEndpoint resolve(
    AiModelConfig config,
    AiApiFamily family, {
    String? fallbackPath,
    String method = 'POST',
    String transport = 'json',
  }) {
    final override = config.endpointOverrides[family];
    final resolvedMethod =
        (override?.method?.trim().isNotEmpty == true
            ? override!.method!.trim()
            : method)
            .toUpperCase();
    final resolvedTransport =
        (override?.transport?.trim().isNotEmpty == true
            ? override!.transport!.trim()
            : transport)
            .toLowerCase();
    final url = _resolveUrl(
      config.normalizedBaseUrl,
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
    AiApiFamily family,
    AiEndpointOverride? override, {
    String? fallbackPath,
  }) {
    final queryDefaults = override?.queryDefaults ?? const <String, String>{};
    final explicitUrl = override?.url?.trim() ?? '';
    if (explicitUrl.isNotEmpty) {
      final explicitUri = Uri.parse(explicitUrl);
      final mergedQuery = <String, String>{
        ...queryDefaults,
        ...explicitUri.queryParameters,
      };
      return explicitUri.replace(
        queryParameters: mergedQuery.isEmpty ? null : mergedQuery,
      ).toString();
    }
    final path = (override?.path?.trim().isNotEmpty == true
            ? override!.path!.trim()
            : (fallbackPath ?? _defaultPathFor(family)))
        .trim();
    if (path.isEmpty) return baseUrl;
    final baseUri = Uri.parse(baseUrl);
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final baseSegments = baseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final pathSegments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final overlapLength = _leadingPathOverlap(baseSegments, pathSegments);
    final mergedPathSegments = <String>[
      ...baseSegments,
      ...pathSegments.skip(overlapLength),
    ];
    final mergedQuery = <String, String>{
      ...queryDefaults,
      ...baseUri.queryParameters,
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
    };
  }

  int _leadingPathOverlap(
    List<String> baseSegments,
    List<String> pathSegments,
  ) {
    final maxOverlap =
        baseSegments.length < pathSegments.length
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
