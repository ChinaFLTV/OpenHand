import 'dart:async';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiModelRecord {
  const AiModelRecord({required this.id, required this.payload});

  final String id;
  final Map<String, Object?> payload;
}

class AiModelsListResult {
  const AiModelsListResult({
    required this.models,
    required this.rawResponse,
    this.payload = const <String, Object?>{},
  });

  final List<AiModelRecord> models;
  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiModelsService {
  AiModelsService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  static const int _maxGeminiPages = 20;

  Future<AiModelsListResult> listModels({
    required AiModelConfig model,
    Duration timeout = const Duration(seconds: 60),
    bool paginateGemini = true,
    int pageSize = 100,
  }) async {
    if (model.protocolType == AiProtocolType.gemini && paginateGemini) {
      return _listGeminiModels(
        model: model,
        timeout: timeout,
        pageSize: pageSize,
      );
    }
    const family = AiApiFamily.models;
    final endpoint = _router.resolve(model, family, method: 'GET');
    final response = await _transport.get(
      uri: AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family),
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: family,
        includeJsonContentType: false,
        acceptJson: true,
      ),
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'models',
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'models',
    );
    final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
    return AiModelsListResult(
      models: _parseModelRecords(payload),
      rawResponse: response.body,
      payload: payload,
    );
  }

  Future<AiModelsListResult> _listGeminiModels({
    required AiModelConfig model,
    required Duration timeout,
    required int pageSize,
  }) async {
    const family = AiApiFamily.models;
    final endpoint = _router.resolve(
      model,
      family,
      method: 'GET',
      fallbackPath: 'v1beta/models',
    );
    final headers = AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpoint.headers,
      family: family,
      includeJsonContentType: false,
      acceptJson: true,
    );
    final rawPages = <Map<String, Object?>>[];
    final records = <AiModelRecord>[];
    String? pageToken;
    for (var page = 0; page < _maxGeminiPages; page++) {
      final uri = AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family)
          .replace(
            queryParameters: <String, String>{
              ...Uri.parse(endpoint.url).queryParameters,
              ...AiOperationHttp.stringMap(
                AiOperationHttp.extrasForFamily(
                  model,
                  family,
                )[AiOperationHttp.extrasQueryKey],
              ),
              if (pageSize > 0) 'pageSize': '$pageSize',
              if (pageToken != null) 'pageToken': pageToken,
            },
          );
      final response = await _transport.get(
        uri: uri,
        headers: headers,
        timeout: timeout,
      );
      AiOperationHttp.throwIfFailed(
        statusCode: response.statusCode,
        body: response.body,
        contextHint: 'models/gemini',
      );
      final decoded = AiOperationHttp.decodeJsonResponse(
        response.body,
        contextHint: 'models/gemini',
      );
      final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
      rawPages.add(payload);
      records.addAll(_parseModelRecords(payload));
      final next = '${payload['nextPageToken'] ?? ''}'.trim();
      if (next.isEmpty) break;
      pageToken = next;
    }
    final deduped = _dedupeRecords(records);
    return AiModelsListResult(
      models: deduped,
      rawResponse: rawPages.toString(),
      payload: <String, Object?>{'pages': rawPages},
    );
  }

  List<AiModelRecord> _parseModelRecords(Map<String, Object?> payload) {
    final rawList = payload['data'] ?? payload['models'];
    if (rawList is! List) return const <AiModelRecord>[];
    final records = <AiModelRecord>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final recordPayload = Map<String, Object?>.from(item);
      var id = '${recordPayload['id'] ?? recordPayload['name'] ?? ''}'.trim();
      if (id.startsWith('models/')) {
        id = id.substring('models/'.length);
      }
      if (id.isEmpty) continue;
      records.add(AiModelRecord(id: id, payload: recordPayload));
    }
    return _dedupeRecords(records);
  }

  List<AiModelRecord> _dedupeRecords(List<AiModelRecord> records) {
    final byId = <String, AiModelRecord>{};
    for (final record in records) {
      byId[record.id] = record;
    }
    final result = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return result.toList(growable: false);
  }

  void dispose() {
    _transport.dispose();
  }
}
