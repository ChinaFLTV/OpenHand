import 'dart:async';
import 'dart:convert';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';

class AiFileRecord {
  const AiFileRecord({required this.id, required this.payload});

  final String id;
  final Map<String, Object?> payload;
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
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, Object?> ? decoded['data'] : null;
    final items = <AiFileRecord>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final payload = Map<String, Object?>.from(item);
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
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) return null;
    final id = '${decoded['id'] ?? fileId}'.trim();
    return id.isEmpty ? null : AiFileRecord(id: id, payload: decoded);
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
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) return null;
    final id = '${decoded['id'] ?? ''}'.trim();
    return id.isEmpty ? null : AiFileRecord(id: id, payload: decoded);
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

  Map<String, String> _buildHeaders(
    AiModelConfig model,
    Map<String, String> endpointHeaders, {
    bool jsonContent = true,
  }) {
    final headers = <String, String>{
      if (jsonContent) 'content-type': 'application/json',
      ...model.customHeaders,
      ...endpointHeaders,
    };
    final token = model.token.trim();
    if (token.isNotEmpty && model.authScheme != AiAuthScheme.none) {
      if (model.authScheme == AiAuthScheme.apiKey) {
        headers['x-api-key'] = model.authScheme.apply(token);
      } else {
        headers['authorization'] = model.authScheme.apply(token);
      }
    }
    return headers;
  }

  void _throwIfFailed(int statusCode, String body, String hint) {
    if (statusCode < 200 || statusCode >= 300) {
      throw Exception(
        AiTransportDiagnosticMessages.httpStatus(
          statusCode,
          serverMessage: body,
          contextHint: hint,
        ),
      );
    }
  }

  void dispose() {
    _transport.dispose();
  }
}
