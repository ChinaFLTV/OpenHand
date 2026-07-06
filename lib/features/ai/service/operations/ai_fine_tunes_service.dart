import 'dart:async';

import '../../../../shared/util/input_value_parsing.dart';
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
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
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
    final decoded = AiOperationHttp.decodeSuccessfulJsonResponse(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'fine-tunes',
    );
    final data = decoded is Map<String, Object?> ? decoded['data'] : null;
    final items = <AiFineTuneJob>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final payload = AiOperationHttp.stringKeyedMap(item);
          final job = _jobFromPayload(payload);
          if (job != null) items.add(job);
        }
      }
    }
    return items;
  }

  Future<AiFineTuneJob?> createJob({
    required AiModelConfig model,
    required Map<String, Object?> payload,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) async {
    final endpoint = _router.resolve(model, AiApiFamily.fineTunes);
    final response = await _transport.sendJson(
      uri: Uri.parse(endpoint.url),
      method: endpoint.method,
      headers: _buildHeaders(model, endpoint.headers),
      body: payload,
      timeout: timeout,
    );
    final responsePayload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'fine-tunes/create',
    );
    if (responsePayload.isEmpty) return null;
    return _jobFromPayload(responsePayload);
  }

  Future<AiFineTuneJob?> retrieveJob({
    required AiModelConfig model,
    required String jobId,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
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
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'fine-tunes/retrieve',
    );
    if (payload.isEmpty) return null;
    return _jobFromPayload(payload, fallbackId: jobId);
  }

  Future<List<Map<String, Object?>>> listEvents({
    required AiModelConfig model,
    required String jobId,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
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
    final decoded = AiOperationHttp.decodeSuccessfulJsonResponse(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'fine-tunes/events',
    );
    final data = decoded is Map<String, Object?> ? decoded['data'] : null;
    if (data is! List) return const <Map<String, Object?>>[];
    return data
        .whereType<Map>()
        .map(AiOperationHttp.stringKeyedMap)
        .toList(growable: false);
  }

  AiFineTuneJob? _jobFromPayload(
    Map<String, Object?> payload, {
    String? fallbackId,
  }) {
    final id =
        optionalStringFromValue(payload['id']) ?? nullIfBlank(fallbackId);
    return id == null ? null : AiFineTuneJob(id: id, payload: payload);
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

  void dispose() {
    _transport.dispose();
  }
}
