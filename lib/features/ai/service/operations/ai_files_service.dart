import 'dart:async';

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
    this.contentType = '',
  });

  final String content;
  final String rawResponse;
  final String contentType;
}

class AiFilesService {
  AiFilesService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<List<AiFileRecord>> listFiles({
    required AiModelConfig model,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(model, AiApiFamily.files, method: 'GET');
    final response = await _transport.get(
      uri: Uri.parse(endpoint.url),
      headers: _buildHeaders(model, endpoint.headers),
      timeout: timeout,
    );
    _throwIfFailed(response.statusCode, response.body, 'files');
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'files',
    );
    final data = decoded is Map<String, Object?> ? decoded['data'] : null;
    final items = <AiFileRecord>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final payload = AiOperationHttp.stringKeyedMap(item);
          final id = '${payload['id'] ?? ''}'.trim();
          if (id.isNotEmpty) {
            items.add(AiFileRecord(id: id, payload: payload));
          }
        }
      }
    }
    return items;
  }

  Future<AiFileRecord?> retrieveFile({
    required AiModelConfig model,
    required String fileId,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.files,
      method: 'GET',
      fallbackPath: 'v1/files/$fileId',
    );
    final response = await _transport.get(
      uri: Uri.parse(endpoint.url),
      headers: _buildHeaders(model, endpoint.headers),
      timeout: timeout,
    );
    _throwIfFailed(response.statusCode, response.body, 'files/retrieve');
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'files/retrieve',
    );
    final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
    if (payload.isEmpty) return null;
    final id = '${payload['id'] ?? fileId}'.trim();
    return id.isEmpty ? null : AiFileRecord(id: id, payload: payload);
  }

  Future<AiFileRecord?> uploadFile({
    required AiModelConfig model,
    required String filePath,
    String purpose = 'assistants',
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final endpoint = _router.resolve(model, AiApiFamily.files);
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
    _throwIfFailed(response.statusCode, response.body, 'files/create');
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'files/create',
    );
    final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
    if (payload.isEmpty) return null;
    final id = '${payload['id'] ?? ''}'.trim();
    return id.isEmpty ? null : AiFileRecord(id: id, payload: payload);
  }

  Future<void> deleteFile({
    required AiModelConfig model,
    required String fileId,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.files,
      method: 'DELETE',
      fallbackPath: 'v1/files/$fileId',
    );
    final response = await _transport.sendJson(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: _buildHeaders(model, endpoint.headers),
      body: const <String, Object?>{},
      timeout: timeout,
    );
    _throwIfFailed(response.statusCode, response.body, 'files/delete');
  }

  Future<AiFileContentResult> retrieveFileContent({
    required AiModelConfig model,
    required String fileId,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.files,
      method: 'GET',
      fallbackPath: 'v1/files/${Uri.encodeComponent(fileId.trim())}/content',
    );
    final response = await _transport.get(
      uri: Uri.parse(endpoint.url),
      headers: _buildHeaders(model, endpoint.headers, jsonContent: false),
      timeout: timeout,
    );
    _throwIfFailed(response.statusCode, response.body, 'files/content');
    return AiFileContentResult(
      content: response.body,
      rawResponse: response.body,
      contentType: (response.headers['content-type'] ?? '').trim(),
    );
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

  void _throwIfFailed(int statusCode, String body, String hint) {
    AiOperationHttp.throwIfFailed(
      statusCode: statusCode,
      body: body,
      contextHint: hint,
    );
  }

  void dispose() {
    _transport.dispose();
  }
}
