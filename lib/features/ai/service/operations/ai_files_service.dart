import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiFileRecord {
  const AiFileRecord({required this.id, required this.payload});

  final String id;
  final Map<String, Object?> payload;
}

class AiFileContentResult {
  const AiFileContentResult({
    required this.content,
    required this.rawResponse,
    this.bytes = const <int>[],
    this.contentType = '',
  });

  final String content;
  final String rawResponse;
  final List<int> bytes;
  final String contentType;
}

class AiFileDownloadResult {
  const AiFileDownloadResult({
    required this.filePath,
    required this.bytesWritten,
    required this.contentType,
    required this.headers,
  });

  final String filePath;
  final int bytesWritten;
  final String contentType;
  final Map<String, String> headers;
}

class AiFilesService {
  AiFilesService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient(),
      _ownsTransport = transport == null;

  static const Set<String> _miniMaxUploadPurposes = <String>{
    'voice_clone',
    'prompt_audio',
    't2a_async_input',
    'video_understanding',
  };
  static const Set<String> _miniMaxListPurposes = <String>{
    'voice_clone',
    'prompt_audio',
    't2a_async_input',
  };
  static const Set<String> _miniMaxDeletePurposes = <String>{
    'voice_clone',
    'prompt_audio',
    't2a_async',
    't2a_async_input',
    'video_generation',
  };

  final AiEndpointRouter _router;
  final AiTransportClient _transport;
  final bool _ownsTransport;

  Future<List<AiFileRecord>> listFiles({
    required AiModelConfig model,
    String? purpose,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) async {
    final miniMax = model.protocolType == AiProtocolType.minimax;
    final normalizedPurpose = nullIfBlank(purpose);
    if (miniMax && normalizedPurpose == null) {
      throw ArgumentError.value(
        purpose,
        'purpose',
        'MiniMax file listing requires a purpose.',
      );
    }
    if (miniMax) {
      _validateMiniMaxPurpose(
        normalizedPurpose!,
        _miniMaxListPurposes,
        operation: 'listing',
      );
    }
    final endpoint = miniMax
        ? _router.resolveProviderPath(
            model,
            AiApiFamily.files,
            path: 'v1/files/list',
            method: 'GET',
          )
        : _router.resolve(model, AiApiFamily.files, method: 'GET');
    final baseUri = Uri.parse(endpoint.url);
    final uri = baseUri.replace(
      queryParameters: <String, String>{
        ...baseUri.queryParameters,
        if (normalizedPurpose != null) 'purpose': normalizedPurpose,
      },
    );
    final response = await _transport.get(
      uri: uri,
      headers: _buildHeaders(model, endpoint.headers),
      timeout: timeout,
    );
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'files',
    );
    AiOperationHttp.throwIfProviderFailed(payload, contextHint: 'files');
    final data = payload[miniMax ? 'files' : 'data'];
    final items = <AiFileRecord>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final payload = AiOperationHttp.stringKeyedMap(item);
          final record = _recordFromPayload(payload);
          if (record != null) items.add(record);
        }
      }
    }
    return items;
  }

  Future<AiFileRecord?> retrieveFile({
    required AiModelConfig model,
    required String fileId,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) async {
    final miniMax = model.protocolType == AiProtocolType.minimax;
    if (miniMax) _miniMaxFileId(fileId);
    final endpoint = miniMax
        ? _router.resolveProviderPath(
            model,
            AiApiFamily.files,
            path: 'v1/files/retrieve',
            method: 'GET',
          )
        : _router.resolve(
            model,
            AiApiFamily.files,
            method: 'GET',
            fallbackPath: 'v1/files/${Uri.encodeComponent(fileId.trim())}',
          );
    final endpointUri = Uri.parse(endpoint.url);
    final uri = miniMax
        ? endpointUri.replace(
            queryParameters: <String, String>{
              ...endpointUri.queryParameters,
              'file_id': fileId.trim(),
            },
          )
        : endpointUri;
    final response = await _transport.get(
      uri: uri,
      headers: _buildHeaders(model, endpoint.headers),
      timeout: timeout,
    );
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'files/retrieve',
    );
    AiOperationHttp.throwIfProviderFailed(
      payload,
      contextHint: 'files/retrieve',
    );
    if (payload.isEmpty) return null;
    final recordPayload = model.protocolType == AiProtocolType.minimax
        ? AiOperationHttp.stringKeyedMap(payload['file'])
        : payload;
    return _recordFromPayload(recordPayload, fallbackId: fileId);
  }

  Future<AiFileRecord?> uploadFile({
    required AiModelConfig model,
    required String filePath,
    String purpose = 'assistants',
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final miniMax = model.protocolType == AiProtocolType.minimax;
    if (miniMax) {
      _validateMiniMaxPurpose(
        purpose,
        _miniMaxUploadPurposes,
        operation: 'upload',
      );
      await _validateMiniMaxUploadFile(filePath, purpose);
    }
    final endpoint = miniMax
        ? _router.resolveProviderPath(
            model,
            AiApiFamily.files,
            path: 'v1/files/upload',
          )
        : _router.resolve(model, AiApiFamily.files);
    final response = await _transport.sendMultipart(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: _buildHeaders(model, endpoint.headers, jsonContent: false),
      body: <String, Object?>{
        'purpose': purpose,
        'file': AiMultipartUploadFile(filePath: filePath),
      },
      timeout: timeout,
    );
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'files/create',
    );
    AiOperationHttp.throwIfProviderFailed(payload, contextHint: 'files/create');
    if (payload.isEmpty) return null;
    final recordPayload = model.protocolType == AiProtocolType.minimax
        ? AiOperationHttp.stringKeyedMap(payload['file'])
        : payload;
    return _recordFromPayload(recordPayload);
  }

  Future<void> deleteFile({
    required AiModelConfig model,
    required String fileId,
    String? purpose,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) async {
    final miniMax = model.protocolType == AiProtocolType.minimax;
    final normalizedPurpose = nullIfBlank(purpose);
    if (miniMax && normalizedPurpose == null) {
      throw ArgumentError.value(
        purpose,
        'purpose',
        'MiniMax file deletion requires a purpose.',
      );
    }
    if (miniMax) {
      _validateMiniMaxPurpose(
        normalizedPurpose!,
        _miniMaxDeletePurposes,
        operation: 'deletion',
      );
    }
    final endpoint = miniMax
        ? _router.resolveProviderPath(
            model,
            AiApiFamily.files,
            path: 'v1/files/delete',
          )
        : _router.resolve(
            model,
            AiApiFamily.files,
            method: 'DELETE',
            fallbackPath: 'v1/files/${Uri.encodeComponent(fileId.trim())}',
          );
    final response = await _transport.sendJson(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: _buildHeaders(model, endpoint.headers),
      body: <String, Object?>{
        if (miniMax) 'file_id': _miniMaxFileId(fileId),
        if (miniMax) 'purpose': normalizedPurpose,
      },
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'files/delete',
    );
    if (response.body.trim().isNotEmpty) {
      final payload = AiOperationHttp.decodeJsonResponse(
        response.body,
        contextHint: 'files/delete',
      );
      AiOperationHttp.throwIfProviderFailed(
        AiOperationHttp.jsonMapOrEmpty(payload),
        contextHint: 'files/delete',
      );
    }
  }

  Future<AiFileContentResult> retrieveFileContent({
    required AiModelConfig model,
    required String fileId,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) async {
    final miniMax = model.protocolType == AiProtocolType.minimax;
    final request = _resolveFileContentRequest(model, fileId);
    final response = await _transport.get(
      uri: request.uri,
      headers: _buildHeaders(
        model,
        request.endpoint.headers,
        jsonContent: false,
      ),
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'files/content',
    );
    final contentType = lowercaseStringFromValue(
      response.headers['content-type'],
    );
    if (miniMax && contentType.contains('json') && response.body.isNotEmpty) {
      final payload = AiOperationHttp.decodeSuccessfulJsonMap(
        statusCode: response.statusCode,
        body: response.body,
        contextHint: 'files/content',
      );
      AiOperationHttp.throwIfProviderFailed(
        payload,
        contextHint: 'files/content',
      );
    }
    return AiFileContentResult(
      content: response.body,
      rawResponse: response.body,
      bytes: response.bodyBytes,
      contentType: stringFromValue(response.headers['content-type']),
    );
  }

  Future<AiFileDownloadResult> downloadFileContent({
    required AiModelConfig model,
    required String fileId,
    required File destination,
    Duration timeout = const Duration(minutes: 10),
    int maxBytes = defaultAiTransportFileDownloadMaxBytes,
  }) async {
    final miniMax = model.protocolType == AiProtocolType.minimax;
    final request = _resolveFileContentRequest(model, fileId);
    final response = await _transport.downloadToFile(
      uri: request.uri,
      headers: _buildHeaders(
        model,
        request.endpoint.headers,
        jsonContent: false,
      ),
      timeout: timeout,
      destination: destination,
      maxBytes: maxBytes,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.errorBody,
      contextHint: 'files/content/download',
    );
    final filePath = response.filePath;
    if (filePath == null) {
      throw StateError('Successful file download did not create a file.');
    }
    final contentType = lowercaseStringFromValue(
      response.headers['content-type'],
    );
    if (miniMax && contentType.contains('json')) {
      try {
        final body = await readBoundedFileString(
          File(filePath),
          maxBytes: defaultAiTransportResponseMaxBytes,
        );
        final payload = AiOperationHttp.decodeSuccessfulJsonMap(
          statusCode: response.statusCode,
          body: body,
          contextHint: 'files/content/download',
        );
        AiOperationHttp.throwIfProviderFailed(
          payload,
          contextHint: 'files/content/download',
        );
        throw StateError(
          'MiniMax file content endpoint returned JSON instead of a file.',
        );
      } finally {
        try {
          await File(filePath).delete();
        } on FileSystemException {
          // Preserve the provider error even when partial-file cleanup fails.
        }
      }
    }
    return AiFileDownloadResult(
      filePath: filePath,
      bytesWritten: response.bytesWritten,
      contentType: contentType,
      headers: response.headers,
    );
  }

  ({AiResolvedEndpoint endpoint, Uri uri}) _resolveFileContentRequest(
    AiModelConfig model,
    String fileId,
  ) {
    final miniMax = model.protocolType == AiProtocolType.minimax;
    if (miniMax) _miniMaxFileId(fileId);
    final endpoint = miniMax
        ? _router.resolveProviderPath(
            model,
            AiApiFamily.files,
            path: 'v1/files/retrieve_content',
            method: 'GET',
          )
        : _router.resolve(
            model,
            AiApiFamily.files,
            method: 'GET',
            fallbackPath:
                'v1/files/${Uri.encodeComponent(fileId.trim())}/content',
          );
    final endpointUri = Uri.parse(endpoint.url);
    return (
      endpoint: endpoint,
      uri: miniMax
          ? endpointUri.replace(
              queryParameters: <String, String>{
                ...endpointUri.queryParameters,
                'file_id': fileId.trim(),
              },
            )
          : endpointUri,
    );
  }

  AiFileRecord? _recordFromPayload(
    Map<String, Object?> payload, {
    String? fallbackId,
  }) {
    final id =
        optionalStringFromValue(payload['id']) ??
        optionalStringFromValue(payload['file_id']) ??
        nullIfBlank(fallbackId);
    return id == null ? null : AiFileRecord(id: id, payload: payload);
  }

  int _miniMaxFileId(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 0) {
      throw ArgumentError.value(
        value,
        'fileId',
        'MiniMax file ID must be a non-negative integer.',
      );
    }
    return parsed;
  }

  void _validateMiniMaxPurpose(
    String purpose,
    Set<String> allowed, {
    required String operation,
  }) {
    if (!allowed.contains(purpose)) {
      throw ArgumentError.value(
        purpose,
        'purpose',
        'MiniMax file $operation purpose must be one of ${allowed.join(', ')}.',
      );
    }
  }

  Future<void> _validateMiniMaxUploadFile(
    String filePath,
    String purpose,
  ) async {
    final file = File(filePath);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw ArgumentError.value(filePath, 'filePath', 'File does not exist.');
    }
    final extension = p.extension(filePath).toLowerCase();
    final Set<String> allowedExtensions;
    final int? maxBytes;
    switch (purpose) {
      case 'voice_clone' || 'prompt_audio':
        allowedExtensions = const <String>{'.mp3', '.m4a', '.wav'};
        maxBytes = 20 * kBytesPerMiB;
      case 't2a_async_input':
        allowedExtensions = const <String>{'.txt', '.zip'};
        maxBytes = null;
      case 'video_understanding':
        allowedExtensions = const <String>{'.mp4', '.avi', '.mov', '.mkv'};
        maxBytes = 512 * kBytesPerMiB;
      default:
        return;
    }
    if (!allowedExtensions.contains(extension)) {
      throw ArgumentError.value(
        extension,
        'filePath',
        'MiniMax $purpose files must use ${allowedExtensions.join(', ')}.',
      );
    }
    if (maxBytes != null && stat.size > maxBytes) {
      throw ArgumentError.value(
        stat.size,
        'filePath',
        'MiniMax $purpose files cannot exceed ${formatByteSize(maxBytes)}.',
      );
    }
  }

  Map<String, String> _buildHeaders(
    AiModelConfig model,
    Map<String, String> endpointHeaders, {
    bool jsonContent = true,
  }) {
    return AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpointHeaders,
      includeJsonContentType: jsonContent,
    );
  }

  void dispose() {
    if (_ownsTransport) {
      _transport.dispose();
    }
  }
}
