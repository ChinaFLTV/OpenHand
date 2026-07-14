import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_protocol_adapter.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiVideoGenerationResult {
  const AiVideoGenerationResult({
    required this.rawResponse,
    required this.payload,
    this.id,
    this.status,
  });

  final String rawResponse;
  final Map<String, Object?> payload;
  final String? id;
  final String? status;
}

class AiVideoContentResult {
  const AiVideoContentResult({
    required this.byteLength,
    required this.rawResponse,
    required this.contentType,
    this.filePath,
    this.payload = const <String, Object?>{},
  });

  final int byteLength;
  final String rawResponse;
  final String contentType;
  final String? filePath;
  final Map<String, Object?> payload;

  bool get hasFile => filePath != null;

  Stream<List<int>> openRead() {
    final path = filePath;
    if (path == null) {
      return Stream<List<int>>.value(utf8.encode(rawResponse));
    }
    return File(path).openRead(0, byteLength);
  }
}

class AiVideoGenerationService {
  AiVideoGenerationService({
    AiEndpointRouter? router,
    AiTransportClient? transport,
  }) : _router = router ?? const AiEndpointRouter(),
       _transport = transport ?? AiTransportClient(),
       _ownsTransport = transport == null;

  final AiEndpointRouter _router;
  final AiTransportClient _transport;
  final bool _ownsTransport;

  static const AiApiFamily _family = AiApiFamily.videoGeneration;
  static const String _pathsKey = 'paths';
  static const String _createPathKey = 'create';
  static const String _getPathKey = 'get';
  static const String _contentPathKey = 'content';
  static const String _soraCreatePathKey = 'sora_create';
  static const String _soraGetPathKey = 'sora_get';
  static const String _soraContentPathKey = 'sora_content';
  static const String _klingTextPathKey = 'kling_text';
  static const String _klingImagePathKey = 'kling_image';
  static const String _jimengPathKey = 'jimeng';
  static const String _jimengVersion = '2022-08-31';
  static const String _jimengSubmitAction = 'CVSync2AsyncSubmitTask';
  static const String _jimengResultAction = 'CVSync2AsyncGetResult';
  static const int _maxVideoContentBytes = 2 * kBytesPerGiB;

  Future<AiVideoGenerationResult> createVideoGeneration({
    required AiModelConfig model,
    required String prompt,
    String? image,
    Map<String, Object?> parameters = const <String, Object?>{},
    Duration timeout = const Duration(minutes: 5),
    bool multipart = false,
  }) {
    return _createVideo(
      model: model,
      prompt: prompt,
      image: image,
      parameters: parameters,
      timeout: timeout,
      multipart: multipart,
      pathKey: _createPathKey,
      fallbackPath: 'v1/videos',
      contextHint: 'videos/create',
    );
  }

  Future<AiVideoGenerationResult> getVideoGeneration({
    required AiModelConfig model,
    required String id,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    return _getVideo(
      model: model,
      id: id,
      timeout: timeout,
      pathKey: _getPathKey,
      fallbackPath: 'v1/videos/{id}',
      contextHint: 'videos/get',
    );
  }

  Future<AiVideoContentResult> getVideoContent({
    required AiModelConfig model,
    required String id,
    Duration timeout = const Duration(minutes: 5),
  }) {
    return _getVideoContent(
      model: model,
      id: id,
      timeout: timeout,
      pathKey: _contentPathKey,
      contextHint: 'videos/content',
    );
  }

  Future<AiVideoContentResult> _getVideoContent({
    required AiModelConfig model,
    required String id,
    required Duration timeout,
    required String pathKey,
    required String contextHint,
  }) async {
    final endpoint = _resolveEndpoint(
      model: model,
      method: 'GET',
      pathKey: pathKey,
      fallbackPath: 'v1/videos/{id}/content',
      id: id,
    );
    final destination = await createInlineMediaOutputFile(
      mimeType: 'video/mp4',
    );
    final response = await _transport.downloadToFile(
      uri: AiOperationHttp.uriWithExtraQuery(endpoint.url, model, _family),
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: _family,
        includeJsonContentType: false,
      ),
      timeout: timeout,
      destination: destination,
      maxBytes: _maxVideoContentBytes,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.errorBody,
      contextHint: contextHint,
    );
    final contentType = (response.headers['content-type'] ?? '').trim();
    final filePath = response.filePath;
    if (filePath == null) {
      throw StateError('Successful video download did not create a file.');
    }
    if (response.bytesWritten == 0) {
      try {
        await File(filePath).delete();
      } on FileSystemException {
        // Preserve the empty-content result even if cleanup fails.
      }
      return AiVideoContentResult(
        byteLength: 0,
        rawResponse: '',
        contentType: contentType,
      );
    }
    var rawResponse = '';
    var payload = const <String, Object?>{};
    String? retainedFilePath = filePath;
    if (contentType.toLowerCase().contains('json')) {
      try {
        rawResponse = await readBoundedFileString(
          File(filePath),
          maxBytes: defaultAiTransportResponseMaxBytes,
        );
        payload = AiOperationHttp.jsonMapOrEmpty(
          AiOperationHttp.decodeJsonResponse(
            rawResponse,
            contextHint: contextHint,
          ),
        );
      } finally {
        try {
          await File(filePath).delete();
        } on FileSystemException {
          // The JSON payload remains bounded; cleanup is best effort.
        }
        retainedFilePath = null;
      }
    }
    return AiVideoContentResult(
      byteLength: response.bytesWritten,
      rawResponse: rawResponse,
      contentType: contentType,
      filePath: retainedFilePath,
      payload: payload,
    );
  }

  Future<AiVideoGenerationResult> createSoraVideo({
    required AiModelConfig model,
    required String prompt,
    String? image,
    Map<String, Object?> parameters = const <String, Object?>{},
    Duration timeout = const Duration(minutes: 5),
  }) {
    return _createVideo(
      model: model,
      prompt: prompt,
      image: image,
      parameters: parameters,
      timeout: timeout,
      multipart: true,
      pathKey: _soraCreatePathKey,
      fallbackPath: 'v1/videos',
      contextHint: 'videos/sora/create',
    );
  }

  Future<AiVideoGenerationResult> getSoraVideo({
    required AiModelConfig model,
    required String id,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) {
    return _getVideo(
      model: model,
      id: id,
      timeout: timeout,
      pathKey: _soraGetPathKey,
      fallbackPath: 'v1/videos/{id}',
      contextHint: 'videos/sora/get',
    );
  }

  Future<AiVideoContentResult> getSoraVideoContent({
    required AiModelConfig model,
    required String id,
    Duration timeout = const Duration(minutes: 5),
  }) {
    return _getVideoContent(
      model: model,
      id: id,
      timeout: timeout,
      pathKey: _soraContentPathKey,
      contextHint: 'videos/sora/content',
    );
  }

  Future<AiVideoGenerationResult> createKlingTextToVideo({
    required AiModelConfig model,
    required String prompt,
    Map<String, Object?> parameters = const <String, Object?>{},
    Duration timeout = const Duration(minutes: 5),
  }) {
    return _createVideo(
      model: model,
      prompt: prompt,
      parameters: parameters,
      timeout: timeout,
      pathKey: _klingTextPathKey,
      fallbackPath: 'v1/videos/kling/text2video',
      contextHint: 'videos/kling/text2video',
    );
  }

  Future<AiVideoGenerationResult> createKlingImageToVideo({
    required AiModelConfig model,
    required String prompt,
    required String image,
    Map<String, Object?> parameters = const <String, Object?>{},
    Duration timeout = const Duration(minutes: 5),
  }) {
    return _createVideo(
      model: model,
      prompt: prompt,
      image: image,
      parameters: parameters,
      timeout: timeout,
      pathKey: _klingImagePathKey,
      fallbackPath: 'v1/videos/kling/image2video',
      contextHint: 'videos/kling/image2video',
    );
  }

  Future<AiVideoGenerationResult> createJimengVideo({
    required AiModelConfig model,
    required String prompt,
    String? image,
    Map<String, Object?> parameters = const <String, Object?>{},
    Duration timeout = const Duration(minutes: 5),
    String version = _jimengVersion,
  }) {
    final query = <String, String>{
      'Action': _jimengSubmitAction,
      'Version': version,
    };
    return _createVideo(
      model: model,
      prompt: prompt,
      image: image,
      parameters: parameters,
      timeout: timeout,
      pathKey: _jimengPathKey,
      fallbackPath: 'v1/videos/jimeng',
      contextHint: 'videos/jimeng/create',
      extraQuery: query,
    );
  }

  Future<AiVideoGenerationResult> getJimengVideo({
    required AiModelConfig model,
    required String id,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
    String version = _jimengVersion,
  }) {
    return _getVideo(
      model: model,
      id: id,
      timeout: timeout,
      pathKey: _jimengPathKey,
      fallbackPath: 'v1/videos/jimeng',
      contextHint: 'videos/jimeng/get',
      extraQuery: <String, String>{
        'Action': _jimengResultAction,
        'Version': version,
      },
    );
  }

  Future<AiVideoGenerationResult> _createVideo({
    required AiModelConfig model,
    required String prompt,
    required Duration timeout,
    required String pathKey,
    required String fallbackPath,
    required String contextHint,
    String? image,
    Map<String, Object?> parameters = const <String, Object?>{},
    bool multipart = false,
    Map<String, String> extraQuery = const <String, String>{},
  }) async {
    final endpoint = _resolveEndpoint(
      model: model,
      method: model.requestMethod,
      pathKey: pathKey,
      fallbackPath: fallbackPath,
    );
    final baseBody = <String, Object?>{
      'model': model.resolveOperationModelId(_family),
      'prompt': prompt,
      if (nullIfBlank(image) case final imageValue?) 'image': imageValue,
      ...parameters,
    };
    final body = AiOperationHttp.mergeBodyExtras(model, _family, baseBody);
    final uri = _withQuery(
      AiOperationHttp.uriWithExtraQuery(endpoint.url, model, _family),
      extraQuery,
    );
    final headers = AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpoint.headers,
      family: _family,
      includeJsonContentType: !multipart,
      acceptJson: true,
    );
    final response = multipart
        ? await _transport.sendMultipart(
            uri: uri,
            method: endpoint.method,
            headers: headers,
            body: _multipartBody(body),
            timeout: timeout,
          )
        : await _transport.sendJson(
            uri: uri,
            method: endpoint.method,
            headers: headers,
            body: body,
            timeout: timeout,
          );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: contextHint,
    );
    return _parseVideoResponse(response.body, contextHint: contextHint);
  }

  Future<AiVideoGenerationResult> _getVideo({
    required AiModelConfig model,
    required String id,
    required Duration timeout,
    required String pathKey,
    required String fallbackPath,
    required String contextHint,
    Map<String, String> extraQuery = const <String, String>{},
  }) async {
    final endpoint = _resolveEndpoint(
      model: model,
      method: 'GET',
      pathKey: pathKey,
      fallbackPath: fallbackPath,
      id: id,
    );
    final uri = _withQuery(
      AiOperationHttp.uriWithExtraQuery(endpoint.url, model, _family),
      extraQuery,
    );
    final response = await _transport.get(
      uri: uri,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: _family,
        includeJsonContentType: false,
        acceptJson: true,
      ),
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: contextHint,
    );
    return _parseVideoResponse(response.body, contextHint: contextHint);
  }

  AiResolvedEndpoint _resolveEndpoint({
    required AiModelConfig model,
    required String method,
    required String pathKey,
    required String fallbackPath,
    String? id,
  }) {
    final path = _pathOverride(model, pathKey) ?? fallbackPath;
    return _router.resolve(
      model,
      _family,
      method: method,
      fallbackPath: path.replaceAll('{id}', id ?? ''),
    );
  }

  String? _pathOverride(AiModelConfig model, String key) {
    final extras = AiOperationHttp.extrasForFamily(model, _family);
    final paths = AiOperationHttp.stringKeyedMap(extras[_pathsKey]);
    return optionalStringFromValue(paths[key]) ??
        optionalStringFromValue(extras['${key}_path']);
  }

  Uri _withQuery(Uri uri, Map<String, String> extraQuery) {
    if (extraQuery.isEmpty) return uri;
    return uri.replace(
      queryParameters: <String, String>{...uri.queryParameters, ...extraQuery},
    );
  }

  Map<String, Object?> _multipartBody(Map<String, Object?> body) {
    final result = <String, Object?>{};
    for (final entry in body.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is List || value is Map) {
        result[entry.key] = jsonEncode(value);
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  AiVideoGenerationResult _parseVideoResponse(
    String body, {
    required String contextHint,
  }) {
    final decoded = AiOperationHttp.decodeJsonResponse(
      body,
      contextHint: contextHint,
    );
    final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
    final nested = AiOperationHttp.stringKeyedMap(payload['data']);
    String? pickString(Iterable<Object?> values) {
      for (final value in values) {
        final text = optionalStringFromValue(value);
        if (text != null) return text;
      }
      return null;
    }

    return AiVideoGenerationResult(
      rawResponse: body,
      payload: payload,
      id: pickString(<Object?>[
        payload['id'],
        payload['task_id'],
        payload['video_id'],
        payload['request_id'],
        nested['id'],
        nested['task_id'],
        nested['video_id'],
      ]),
      status: pickString(<Object?>[
        payload['status'],
        payload['state'],
        payload['task_status'],
        nested['status'],
        nested['state'],
        nested['task_status'],
      ]),
    );
  }

  void dispose() {
    if (_ownsTransport) {
      _transport.dispose();
    }
  }
}
