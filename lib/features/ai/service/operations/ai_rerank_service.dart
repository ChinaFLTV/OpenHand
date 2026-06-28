import 'dart:async';
import 'dart:convert';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiRerankItem {
  const AiRerankItem({
    required this.index,
    required this.score,
    this.document,
    this.payload = const <String, Object?>{},
  });

  final int index;
  final double score;
  final Object? document;
  final Map<String, Object?> payload;
}

class AiRerankResult {
  const AiRerankResult({
    required this.items,
    required this.rawResponse,
    this.payload = const <String, Object?>{},
  });

  final List<AiRerankItem> items;
  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiRerankService {
  AiRerankService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  static const AiRerankResult _emptyResult = AiRerankResult(
    items: <AiRerankItem>[],
    rawResponse: '',
    payload: <String, Object?>{'results': <Object?>[]},
  );

  static const List<_RerankRequestStrategy> _requestStrategies =
      <_RerankRequestStrategy>[
        _DashScopeCompatibleRerankStrategy(),
        _DashScopeLegacyRerankStrategy(),
        _VoyageRerankStrategy(),
        _CohereRerankStrategy(),
        _OpenAiCompatibleRerankStrategy(),
      ];

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<AiRerankResult> rerank({
    required AiModelConfig model,
    required String query,
    required List<Object> documents,
    Duration timeout = const Duration(seconds: 60),
    int? topN,
    bool? returnDocuments,
    int? maxChunksPerDoc,
    int? maxTokensPerDoc,
    int? priority,
    String? instruction,
    bool? truncation,
  }) async {
    if (documents.isEmpty) return _emptyResult;
    final plan = _buildRequestPlan(
      model: model,
      query: query,
      documents: documents,
      topN: topN,
      returnDocuments: returnDocuments,
      maxChunksPerDoc: maxChunksPerDoc,
      maxTokensPerDoc: maxTokensPerDoc,
      priority: priority,
      instruction: instruction,
      truncation: truncation,
    );
    return _sendPlan(
      model: model,
      documents: documents,
      plan: plan,
      timeout: timeout,
    );
  }

  Future<AiRerankResult> _sendPlan({
    required AiModelConfig model,
    required List<Object> documents,
    required _RerankRequestPlan plan,
    required Duration timeout,
  }) async {
    const family = AiApiFamily.rerank;
    final endpoint = _router.resolve(
      model,
      family,
      fallbackPath: plan.fallbackPath,
      method: model.requestMethod,
    );
    final response = await _transport.sendJson(
      uri: AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: family,
      ),
      body: plan.body,
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: plan.contextHint,
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: plan.contextHint,
    );
    final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
    return AiRerankResult(
      items: _parseItems(payload, documents: documents),
      rawResponse: response.body,
      payload: payload,
    );
  }

  _RerankRequestPlan _buildRequestPlan({
    required AiModelConfig model,
    required String query,
    required List<Object> documents,
    int? topN,
    bool? returnDocuments,
    int? maxChunksPerDoc,
    int? maxTokensPerDoc,
    int? priority,
    String? instruction,
    bool? truncation,
  }) {
    final context = _RerankRequestContext(
      model: model,
      query: query,
      documents: documents,
      topN: topN,
      returnDocuments: returnDocuments,
      maxChunksPerDoc: maxChunksPerDoc,
      maxTokensPerDoc: maxTokensPerDoc,
      priority: priority,
      instruction: instruction,
      truncation: truncation,
    );
    for (final strategy in _requestStrategies) {
      if (strategy.matches(context)) return strategy.build(context);
    }
    throw StateError('No rerank request strategy matched.');
  }

  List<AiRerankItem> _parseItems(
    Map<String, Object?> payload, {
    required List<Object> documents,
  }) {
    final rawResults = _firstRerankList(payload);
    final items = <AiRerankItem>[];
    for (final item in rawResults) {
      if (item is! Map) continue;
      final itemPayload = Map<String, Object?>.from(item);
      final index = _intValue(
        itemPayload['index'] ??
            itemPayload['document_index'] ??
            itemPayload['documentIndex'],
      );
      final score = _doubleValue(
        itemPayload['relevance_score'] ??
            itemPayload['relevanceScore'] ??
            itemPayload['score'] ??
            itemPayload['rerank_score'] ??
            itemPayload['rerankScore'] ??
            itemPayload['relevance'] ??
            itemPayload['similarity'] ??
            itemPayload['logit'],
      );
      if (index == null || score == null) continue;
      items.add(
        AiRerankItem(
          index: index,
          score: score,
          document: itemPayload['document'] ?? _documentAt(documents, index),
          payload: itemPayload,
        ),
      );
    }
    return items;
  }

  void dispose() {
    _transport.dispose();
  }
}

class _RerankRequestPlan {
  const _RerankRequestPlan({
    required this.body,
    required this.contextHint,
    this.fallbackPath,
  });

  final Map<String, Object?> body;
  final String contextHint;
  final String? fallbackPath;
}

class _RerankRequestContext {
  _RerankRequestContext({
    required this.model,
    required this.query,
    required this.documents,
    this.topN,
    this.returnDocuments,
    this.maxChunksPerDoc,
    this.maxTokensPerDoc,
    this.priority,
    this.instruction,
    this.truncation,
  }) : modelId = model.resolveOperationModelId(AiApiFamily.rerank),
       profile = model.profileFor(
         model.resolveOperationModelId(AiApiFamily.rerank),
       );

  final AiModelConfig model;
  final String query;
  final List<Object> documents;
  final int? topN;
  final bool? returnDocuments;
  final int? maxChunksPerDoc;
  final int? maxTokensPerDoc;
  final int? priority;
  final String? instruction;
  final bool? truncation;
  final String modelId;
  final AiModelProfile profile;

  String get normalizedModelId => modelId.toLowerCase();
  String? get profileEndpointPath => _trimmedOrNull(profile.rerankEndpointPath);
  int? get resolvedTopN {
    final requested = topN != null && topN! > 0
        ? topN
        : profile.rerankDefaultTopN;
    if (requested == null || requested <= 0) return null;
    return requested > documents.length ? documents.length : requested;
  }

  bool? get resolvedReturnDocuments => returnDocuments;
  String? get resolvedInstruction =>
      _trimmedOrNull(instruction) ??
      _trimmedOrNull(profile.rerankDefaultInstruction);
  bool? get resolvedTruncation => truncation ?? profile.rerankDefaultTruncation;
  int? get positiveMaxChunksPerDoc =>
      maxChunksPerDoc == null || maxChunksPerDoc! <= 0 ? null : maxChunksPerDoc;
  int? get positiveMaxTokensPerDoc =>
      maxTokensPerDoc == null || maxTokensPerDoc! <= 0 ? null : maxTokensPerDoc;
  int? get positivePriority =>
      priority == null || priority! < 0 ? null : priority;

  Map<String, Object?> withProfileDefaults(Map<String, Object?> payload) {
    final defaults = profile.defaultParameters;
    if (defaults.isEmpty) return payload;
    return _deepMergeObjectMaps(defaults, payload);
  }

  bool supportsParameter(String key) {
    final parameters = profile.rerankSupportedParameters;
    if (parameters.isEmpty) return true;
    final normalizedKey = key.trim().toLowerCase();
    if (normalizedKey.isEmpty) return false;
    return parameters.any(
      (parameter) => parameter.trim().toLowerCase() == normalizedKey,
    );
  }
}

abstract class _RerankRequestStrategy {
  const _RerankRequestStrategy();

  bool matches(_RerankRequestContext context);

  _RerankRequestPlan build(_RerankRequestContext context);
}

class _DashScopeCompatibleRerankStrategy extends _RerankRequestStrategy {
  const _DashScopeCompatibleRerankStrategy();

  static const String _fallbackPath = 'compatible-mode/v1/reranks';

  @override
  bool matches(_RerankRequestContext context) {
    final endpoint = context.profileEndpointPath?.toLowerCase() ?? '';
    return context.normalizedModelId.startsWith('qwen3-rerank') ||
        endpoint.contains('/reranks') ||
        endpoint.endsWith('reranks');
  }

  @override
  _RerankRequestPlan build(_RerankRequestContext context) {
    const family = AiApiFamily.rerank;
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      context.withProfileDefaults(<String, Object?>{
        'model': context.modelId,
        'query': context.query,
        'documents': _textDocuments(context.documents),
        if (context.supportsParameter('top_n') && context.resolvedTopN != null)
          'top_n': context.resolvedTopN,
        if (context.supportsParameter('instruct') &&
            context.resolvedInstruction != null)
          'instruct': context.resolvedInstruction,
      }),
    );
    return _RerankRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath ?? _fallbackPath,
      contextHint: 'rerank/dashscope/compatible',
    );
  }
}

class _DashScopeLegacyRerankStrategy extends _RerankRequestStrategy {
  const _DashScopeLegacyRerankStrategy();

  static const String _fallbackPath =
      'api/v1/services/rerank/text-rerank/text-rerank';

  @override
  bool matches(_RerankRequestContext context) {
    final endpoint = context.profileEndpointPath?.toLowerCase() ?? '';
    return context.model.protocolType == AiProtocolType.qwen &&
        (endpoint.contains('text-rerank') ||
            context.normalizedModelId.startsWith('gte-rerank') ||
            context.normalizedModelId.startsWith('qwen3-vl-rerank'));
  }

  @override
  _RerankRequestPlan build(_RerankRequestContext context) {
    const family = AiApiFamily.rerank;
    final parameters = <String, Object?>{
      if (context.supportsParameter('parameters.top_n') &&
          context.resolvedTopN != null)
        'top_n': context.resolvedTopN,
      if (context.supportsParameter('parameters.return_documents') &&
          context.resolvedReturnDocuments != null)
        'return_documents': context.resolvedReturnDocuments,
      if (context.supportsParameter('parameters.instruct') &&
          context.resolvedInstruction != null)
        'instruct': context.resolvedInstruction,
    };
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      context.withProfileDefaults(<String, Object?>{
        'model': context.modelId,
        'input': <String, Object?>{
          'query': context.query,
          'documents': context.documents,
        },
        if (parameters.isNotEmpty) 'parameters': parameters,
      }),
    );
    return _RerankRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath ?? _fallbackPath,
      contextHint: 'rerank/dashscope/text-rerank',
    );
  }
}

class _VoyageRerankStrategy extends _RerankRequestStrategy {
  const _VoyageRerankStrategy();

  @override
  bool matches(_RerankRequestContext context) {
    final baseUrl = context.model.baseUrl.toLowerCase();
    final profileUsesTopK = context.profile.rerankSupportedParameters.any(
      (parameter) => parameter.trim().toLowerCase() == 'top_k',
    );
    return profileUsesTopK ||
        context.normalizedModelId.startsWith('voyage-rerank') ||
        _isVoyageBaseUrl(baseUrl);
  }

  @override
  _RerankRequestPlan build(_RerankRequestContext context) {
    const family = AiApiFamily.rerank;
    final forceVoyageDialect = _isVoyageBaseUrl(
      context.model.baseUrl.toLowerCase(),
    );
    final resolvedTruncation =
        context.resolvedTruncation ?? (forceVoyageDialect ? true : null);
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      context.withProfileDefaults(<String, Object?>{
        'model': context.modelId,
        'query': context.query,
        'documents': _textDocuments(context.documents),
        if ((forceVoyageDialect || context.supportsParameter('top_k')) &&
            context.resolvedTopN != null)
          'top_k': context.resolvedTopN,
        if ((forceVoyageDialect ||
                context.supportsParameter('return_documents')) &&
            context.resolvedReturnDocuments != null)
          'return_documents': context.resolvedReturnDocuments,
        if ((forceVoyageDialect || context.supportsParameter('truncation')) &&
            resolvedTruncation != null)
          'truncation': resolvedTruncation,
      }),
    );
    return _RerankRequestPlan(
      body: body,
      fallbackPath: forceVoyageDialect
          ? 'v1/rerank'
          : context.profileEndpointPath ?? 'v1/rerank',
      contextHint: 'rerank/voyage',
    );
  }

  bool _isVoyageBaseUrl(String baseUrl) {
    return baseUrl.contains('voyageai') || baseUrl.contains('voyage.ai');
  }
}

class _CohereRerankStrategy extends _RerankRequestStrategy {
  const _CohereRerankStrategy();

  @override
  bool matches(_RerankRequestContext context) {
    final baseUrl = context.model.baseUrl.toLowerCase();
    return baseUrl.contains('cohere') ||
        context.normalizedModelId.contains('rerank') &&
            context.profile.rerankSupportedParameters.contains(
              'max_tokens_per_doc',
            );
  }

  @override
  _RerankRequestPlan build(_RerankRequestContext context) {
    const family = AiApiFamily.rerank;
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      context.withProfileDefaults(<String, Object?>{
        'model': context.modelId,
        'query': context.query,
        'documents': _textDocuments(context.documents),
        if (context.supportsParameter('top_n') && context.resolvedTopN != null)
          'top_n': context.resolvedTopN,
        if (context.supportsParameter('max_tokens_per_doc') &&
            context.positiveMaxTokensPerDoc != null)
          'max_tokens_per_doc': context.positiveMaxTokensPerDoc,
        if (context.supportsParameter('priority') &&
            context.positivePriority != null)
          'priority': context.positivePriority,
      }),
    );
    return _RerankRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath ?? 'v2/rerank',
      contextHint: 'rerank/cohere',
    );
  }
}

class _OpenAiCompatibleRerankStrategy extends _RerankRequestStrategy {
  const _OpenAiCompatibleRerankStrategy();

  @override
  bool matches(_RerankRequestContext context) => true;

  @override
  _RerankRequestPlan build(_RerankRequestContext context) {
    const family = AiApiFamily.rerank;
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      context.withProfileDefaults(<String, Object?>{
        'model': context.modelId,
        'query': context.query,
        'documents': context.documents,
        if (context.supportsParameter('top_n') && context.resolvedTopN != null)
          'top_n': context.resolvedTopN,
        if (context.supportsParameter('return_documents') &&
            context.resolvedReturnDocuments != null)
          'return_documents': context.resolvedReturnDocuments,
        if (context.supportsParameter('max_chunks_per_doc') &&
            context.positiveMaxChunksPerDoc != null)
          'max_chunks_per_doc': context.positiveMaxChunksPerDoc,
        if (context.supportsParameter('instruct') &&
            context.resolvedInstruction != null)
          'instruct': context.resolvedInstruction,
      }),
    );
    return _RerankRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath,
      contextHint: 'rerank',
    );
  }
}

List<Object?> _firstRerankList(Map<String, Object?> payload) {
  for (final candidate in <Object?>[
    payload['results'],
    payload['data'],
    payload['rankings'],
    AiOperationHttp.stringKeyedMap(payload['output'])['results'],
    AiOperationHttp.stringKeyedMap(payload['output'])['data'],
    AiOperationHttp.stringKeyedMap(payload['output'])['rankings'],
    AiOperationHttp.stringKeyedMap(payload['result'])['results'],
    AiOperationHttp.stringKeyedMap(payload['result'])['data'],
    AiOperationHttp.stringKeyedMap(payload['result'])['rankings'],
  ]) {
    if (candidate is List) return candidate;
  }
  return const <Object?>[];
}

List<String> _textDocuments(List<Object> documents) {
  return documents.map(_documentText).toList(growable: false);
}

String _documentText(Object document) {
  if (document is String) return document;
  if (document is Map<String, Object?>) {
    final text = document['text'];
    if (text is String && text.trim().isNotEmpty) return text;
    return jsonEncode(document);
  }
  if (document is Map) {
    final map = Map<String, Object?>.from(document);
    final text = map['text'];
    if (text is String && text.trim().isNotEmpty) return text;
    return jsonEncode(map);
  }
  if (document is Iterable || document is num || document is bool) {
    return jsonEncode(document);
  }
  return '$document';
}

Object? _documentAt(List<Object> documents, int index) {
  if (index < 0 || index >= documents.length) return null;
  return documents[index];
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _doubleValue(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

Map<String, Object?> _deepMergeObjectMaps(
  Map<String, Object?> defaults,
  Map<String, Object?> overrides,
) {
  if (defaults.isEmpty) return overrides;
  if (overrides.isEmpty) return Map<String, Object?>.from(defaults);
  final merged = Map<String, Object?>.from(defaults);
  for (final entry in overrides.entries) {
    final defaultValue = merged[entry.key];
    final defaultMap = AiOperationHttp.stringKeyedMap(defaultValue);
    final overrideMap = AiOperationHttp.stringKeyedMap(entry.value);
    if (_deepMergeableRerankBodyKeys.contains(entry.key) &&
        defaultMap.isNotEmpty &&
        overrideMap.isNotEmpty) {
      merged[entry.key] = _deepMergeObjectMaps(defaultMap, overrideMap);
    } else {
      merged[entry.key] = entry.value;
    }
  }
  return merged;
}

const Set<String> _deepMergeableRerankBodyKeys = <String>{
  'metadata',
  'parameters',
  'input',
};

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
