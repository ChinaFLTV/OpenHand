import 'dart:async';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

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
    final endpoint = _router.resolve(
      model,
      AiApiFamily.fineTunes,
      method: 'GET',
    );
    final response = await _transport.get(
      uri: Uri.parse(endpoint.url),
      headers: _buildHeaders(model, endpoint.headers),
      timeout: timeout,
    );
    _throwIfFailed(response.statusCode, response.body, 'fine-tunes');
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'fine-tunes',
    );
    final data = decoded is Map<String, Object?> ? decoded['data'] : null;
    final items = <AiFineTuneJob>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final payload = AiOperationHttp.stringKeyedMap(item);
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
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'fine-tunes/create',
    );
    final responsePayload = AiOperationHttp.jsonMapOrEmpty(decoded);
    if (responsePayload.isEmpty) return null;
    final id = '${responsePayload['id'] ?? ''}'.trim();
    return id.isEmpty ? null : AiFineTuneJob(id: id, payload: responsePayload);
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
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'fine-tunes/retrieve',
    );
    final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
    if (payload.isEmpty) return null;
    final id = '${payload['id'] ?? jobId}'.trim();
    return id.isEmpty ? null : AiFineTuneJob(id: id, payload: payload);
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
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'fine-tunes/events',
    );
    final data = decoded is Map<String, Object?> ? decoded['data'] : null;
    if (data is! List) return const <Map<String, Object?>>[];
    return data
        .whereType<Map>()
        .map(AiOperationHttp.stringKeyedMap)
        .toList(growable: false);
  }

  Map<String, String> _buildHeaders(
    AiModelConfig model,
    Map<String, String> endpointHeaders,
  ) {
    return AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpointHeaders,
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
