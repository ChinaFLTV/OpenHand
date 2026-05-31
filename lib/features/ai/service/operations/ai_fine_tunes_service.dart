import 'dart:async';
import 'dart:convert';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';

class AiFineTuneJob {
  const AiFineTuneJob({required this.id, required this.payload});

  final String id;
  final Map<String, Object?> payload;
}

class AiFineTunesService {
  AiFineTunesService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<List<AiFineTuneJob>> listJobs({
    required AiModelConfig model,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(model, AiApiFamily.fineTunes, method: 'GET');
    final response = await _transport.get(
      uri: Uri.parse(endpoint.url),
      headers: _buildHeaders(model, endpoint.headers),
      timeout: timeout,
    );
    _throwIfFailed(response.statusCode, response.body, 'fine-tunes');
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, Object?> ? decoded['data'] : null;
    final items = <AiFineTuneJob>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final payload = Map<String, Object?>.from(item);
          final id = '${payload['id'] ?? ''}'.trim();
          if (id.isNotEmpty) {
            items.add(AiFineTuneJob(id: id, payload: payload));
          }
        }
      }
    }
    return items;
  }

  Future<AiFineTuneJob?> createJob({
    required AiModelConfig model,
    required Map<String, Object?> payload,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(model, AiApiFamily.fineTunes);
    final response = await _transport.sendJson(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: _buildHeaders(model, endpoint.headers),
      body: payload,
      timeout: timeout,
    );
    _throwIfFailed(response.statusCode, response.body, 'fine-tunes/create');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) return null;
    final id = '${decoded['id'] ?? ''}'.trim();
    return id.isEmpty ? null : AiFineTuneJob(id: id, payload: decoded);
  }

  Future<AiFineTuneJob?> retrieveJob({
    required AiModelConfig model,
    required String jobId,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.fineTunes,
      method: 'GET',
      fallbackPath: 'v1/fine-tunes/$jobId',
    );
    final response = await _transport.get(
      uri: Uri.parse(endpoint.url),
      headers: _buildHeaders(model, endpoint.headers),
      timeout: timeout,
    );
    _throwIfFailed(response.statusCode, response.body, 'fine-tunes/retrieve');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) return null;
    final id = '${decoded['id'] ?? jobId}'.trim();
    return id.isEmpty ? null : AiFineTuneJob(id: id, payload: decoded);
  }

  Future<List<Map<String, Object?>>> listEvents({
    required AiModelConfig model,
    required String jobId,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.fineTunes,
      method: 'GET',
      fallbackPath: 'v1/fine-tunes/$jobId/events',
    );
    final response = await _transport.get(
      uri: Uri.parse(endpoint.url),
      headers: _buildHeaders(model, endpoint.headers),
      timeout: timeout,
    );
    _throwIfFailed(response.statusCode, response.body, 'fine-tunes/events');
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, Object?> ? decoded['data'] : null;
    if (data is! List) return const <Map<String, Object?>>[];
    return data
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  Map<String, String> _buildHeaders(
    AiModelConfig model,
    Map<String, String> endpointHeaders,
  ) {
    final headers = <String, String>{
      'content-type': 'application/json',
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
