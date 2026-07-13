import 'dart:async';
import 'dart:convert';

import '../../../../shared/util/input_value_parsing.dart';
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
      _transport = transport ?? AiTransportClient(),
      _ownsTransport = transport == null;

  final AiEndpointRouter _router;
  final AiTransportClient _transport;
  final bool _ownsTransport;

  static const int _maxGeminiPages = 20;
  static const int _defaultGeminiPageSize = 100;
  static const int _maxGeminiPageSize = 1000;
  static const String _geminiModelNamePrefix = 'models/';

  Future<AiModelsListResult> listModels({
    required AiModelConfig model,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
    bool paginateGemini = true,
    int pageSize = _defaultGeminiPageSize,
  }) async {
    if (model.protocolType == AiProtocolType.gemini && paginateGemini) {
      return _listGeminiModels(
        model: model,
        timeout: timeout,
        pageSize: pageSize,
      );
    }
    const family = AiApiFamily.models;
    final endpoint = model.protocolType == AiProtocolType.minimax
        ? _router.resolveProviderPath(
            model,
            family,
            path: 'v1/models',
            method: 'GET',
          )
        : _router.resolve(model, family, method: 'GET');
    final result = await _getModelsJson(
      model: model,
      endpoint: endpoint,
      timeout: timeout,
      contextHint: 'models',
    );
    return AiModelsListResult(
      models: _parseModelRecords(result.payload),
      rawResponse: result.rawResponse,
      payload: result.payload,
    );
  }

  Future<AiModelRecord?> retrieveModel({
    required AiModelConfig model,
    required String modelId,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
  }) async {
    final normalizedModelId = nullIfBlank(modelId);
    if (normalizedModelId == null) {
      throw ArgumentError.value(modelId, 'modelId', 'Model ID is empty.');
    }
    const family = AiApiFamily.models;
    final modelPath = 'v1/models/${Uri.encodeComponent(normalizedModelId)}';
    final endpoint = model.protocolType == AiProtocolType.minimax
        ? _router.resolveProviderPath(
            model,
            family,
            path: modelPath,
            method: 'GET',
          )
        : _router.resolve(
            model,
            family,
            method: 'GET',
            fallbackPath: modelPath,
          );
    final result = await _getModelsJson(
      model: model,
      endpoint: endpoint,
      timeout: timeout,
      contextHint: 'models/retrieve',
    );
    final id = _normalizeModelId(
      optionalStringFromValue(result.payload['id']) ?? normalizedModelId,
    );
    return id == null ? null : AiModelRecord(id: id, payload: result.payload);
  }

  Future<({Map<String, Object?> payload, String rawResponse})> _getModelsJson({
    required AiModelConfig model,
    required AiResolvedEndpoint endpoint,
    required Duration timeout,
    required String contextHint,
  }) async {
    const family = AiApiFamily.models;
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
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: contextHint,
    );
    AiOperationHttp.throwIfProviderFailed(payload, contextHint: contextHint);
    return (payload: payload, rawResponse: response.body);
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
    final effectivePageSize = _safeGeminiPageSize(pageSize);
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
              if (effectivePageSize > 0) 'pageSize': '$effectivePageSize',
              if (pageToken != null) 'pageToken': pageToken,
            },
          );
      final response = await _transport.get(
        uri: uri,
        headers: headers,
        timeout: timeout,
      );
      final payload = AiOperationHttp.decodeSuccessfulJsonMap(
        statusCode: response.statusCode,
        body: response.body,
        contextHint: 'models/gemini',
      );
      rawPages.add(payload);
      records.addAll(_parseModelRecords(payload));
      final next = optionalStringFromValue(payload['nextPageToken']);
      if (next == null || next == pageToken) break;
      pageToken = next;
    }
    final deduped = _dedupeRecords(records);
    return AiModelsListResult(
      models: deduped,
      rawResponse: jsonEncode(<String, Object?>{'pages': rawPages}),
      payload: <String, Object?>{'pages': rawPages},
    );
  }

  int _safeGeminiPageSize(int pageSize) {
    if (pageSize <= 0) return 0;
    if (pageSize > _maxGeminiPageSize) return _maxGeminiPageSize;
    return pageSize;
  }

  List<AiModelRecord> _parseModelRecords(Map<String, Object?> payload) {
    final rawList = payload['data'] ?? payload['models'];
    if (rawList is! List) return const <AiModelRecord>[];
    final records = <AiModelRecord>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final recordPayload = AiOperationHttp.stringKeyedMap(item);
      final id = _normalizeModelId(
        optionalStringFromValue(recordPayload['id']) ??
            optionalStringFromValue(recordPayload['name']),
      );
      if (id == null) continue;
      records.add(AiModelRecord(id: id, payload: recordPayload));
    }
    return _dedupeRecords(records);
  }

  String? _normalizeModelId(String? value) {
    if (value == null) return null;
    final id = value.startsWith(_geminiModelNamePrefix)
        ? value.substring(_geminiModelNamePrefix.length)
        : value;
    return nullIfBlank(id);
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
    if (_ownsTransport) {
      _transport.dispose();
    }
  }
}
