import 'dart:async';
import 'dart:convert';

import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import '../session_io/ai_token_usage_parser.dart';
import '../usage/ai_usage_tracker.dart';
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
      _transport = transport ?? AiTransportClient(),
      _ownsTransport = transport == null;

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
  final bool _ownsTransport;

  Future<AiRerankResult> rerank({
    required AiModelConfig model,
    required String query,
    required List<Object> documents,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
    int? topN,
    bool? returnDocuments,
    int? maxChunksPerDoc,
    int? maxTokensPerDoc,
    int? priority,
    String? instruction,
    bool? truncation,
    Future<void>? cancelSignal,
  }) async {
    if (documents.isEmpty) return _emptyResult;
    final startedAt = DateTime.now().toUtc();
    try {
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
      final result = await _sendPlan(
        model: model,
        documents: documents,
        plan: plan,
        timeout: timeout,
        cancelSignal: cancelSignal,
      );
      AiUsageTracker.instance.recordSuccess(
        model: model,
        apiFamily: AiApiFamily.rerank.storageValue,
        startedAt: startedAt,
        endedAt: DateTime.now().toUtc(),
        inputCharacters:
            query.length +
            documents.fold<int>(0, (sum, item) => sum + '$item'.length),
        outputCharacters: 0,
        usage: _usageFromPayload(result.payload),
        metadata: <String, Object?>{
          'document_count': documents.length,
          'result_count': result.items.length,
        },
      );
      return result;
    } catch (error) {
      AiUsageTracker.instance.recordFailure(
        model: model,
        apiFamily: AiApiFamily.rerank.storageValue,
        startedAt: startedAt,
        endedAt: DateTime.now().toUtc(),
        error: error,
        timeout: timeout,
      );
      rethrow;
    }
  }

  Future<AiRerankResult> _sendPlan({
    required AiModelConfig model,
    required List<Object> documents,
    required _RerankRequestPlan plan,
    required Duration timeout,
    required Future<void>? cancelSignal,
  }) async {
    const family = AiApiFamily.rerank;
    final endpoint = _router.resolve(
      model,
      family,
      fallbackPath: plan.fallbackPath,
      method: model.requestMethod,
    );
    final response = await AiOperationHttp.sendJsonForFamily(
      transport: _transport,
      endpoint: endpoint,
      model: model,
      family: family,
      body: plan.body,
      timeout: timeout,
      cancelSignal: cancelSignal,
    );
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: plan.contextHint,
    );
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
      final itemPayload = AiOperationHttp.stringKeyedMap(item);
      final index = optionalIntFromValue(
        itemPayload['index'] ??
            itemPayload['document_index'] ??
            itemPayload['documentIndex'],
      );
      final score = optionalDoubleFromValue(
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

  AiTokenUsage? _usageFromPayload(Map<String, Object?> payload) {
    final rawUsage = payload['usage'];
    if (rawUsage is Map) {
      return AiTokenUsageParser.parseOpenAi(stringKeyedMapFromValue(rawUsage));
    }
    final meta = payload['meta'];
    if (meta is Map) {
      final metaMap = stringKeyedMapFromValue(meta);
      final billedUnits = metaMap['billed_units'];
      if (billedUnits is Map) {
        return AiTokenUsageParser.parseOpenAi(
          stringKeyedMapFromValue(billedUnits),
        );
      }
    }
    return null;
  }

  void dispose() {
    if (_ownsTransport) {
      _transport.dispose();
    }
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
  }) : modelId = _normalizeRerankRequestModelId(
         model,
         model.resolveOperationModelId(AiApiFamily.rerank),
       ),
       profile = model.profileFor(
         _normalizeRerankRequestModelId(
           model,
           model.resolveOperationModelId(AiApiFamily.rerank),
         ),
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
  String? get profileEndpointPath => nullIfBlank(profile.rerankEndpointPath);
  Map<String, Object?> get textRequestFields => <String, Object?>{
    'model': modelId,
    'query': query,
    'documents': _textDocuments(documents),
  };
  Map<String, Object?> get textRequestFieldsWithTopN => <String, Object?>{
    ...textRequestFields,
    if (supportsParameter('top_n') && resolvedTopN != null)
      'top_n': resolvedTopN,
  };
  int? get resolvedTopN {
    final requested = topN != null && topN! > 0
        ? topN
        : profile.rerankDefaultTopN;
    if (requested == null || requested <= 0) return null;
    return requested > documents.length ? documents.length : requested;
  }

  bool? get resolvedReturnDocuments => returnDocuments;
  String? get resolvedInstruction =>
      nullIfBlank(instruction) ?? nullIfBlank(profile.rerankDefaultInstruction);
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
    return AiOperationHttp.deepMergeObjectMaps(
      defaults,
      payload,
      deepMergeKeys: _deepMergeableRerankBodyKeys,
    );
  }

  _RerankRequestPlan buildPlan({
    required Map<String, Object?> payload,
    required String contextHint,
    String? fallbackPath,
  }) {
    return _RerankRequestPlan(
      body: AiOperationHttp.mergeBodyExtras(
        model,
        AiApiFamily.rerank,
        withProfileDefaults(payload),
      ),
      fallbackPath: fallbackPath,
      contextHint: contextHint,
    );
  }

  bool supportsParameter(String key) {
    final parameters = profile.rerankSupportedParameters;
    if (parameters.isEmpty) return true;
    final normalizedKey = lowercaseStringFromValue(key);
    if (normalizedKey.isEmpty) return false;
    return parameters.any(
      (parameter) => lowercaseStringFromValue(parameter) == normalizedKey,
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
    return context.buildPlan(
      payload: <String, Object?>{
        ...context.textRequestFieldsWithTopN,
        if (context.supportsParameter('instruct') &&
            context.resolvedInstruction != null)
          'instruct': context.resolvedInstruction,
      },
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
    return context.buildPlan(
      payload: <String, Object?>{
        'model': context.modelId,
        'input': <String, Object?>{
          'query': context.query,
          'documents': context.documents,
        },
        if (parameters.isNotEmpty) 'parameters': parameters,
      },
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
      (parameter) => lowercaseStringFromValue(parameter) == 'top_k',
    );
    return profileUsesTopK ||
        context.normalizedModelId.startsWith('voyage-rerank') ||
        _isVoyageBaseUrl(baseUrl);
  }

  @override
  _RerankRequestPlan build(_RerankRequestContext context) {
    final forceVoyageDialect = _isVoyageBaseUrl(
      context.model.baseUrl.toLowerCase(),
    );
    final resolvedTruncation =
        context.resolvedTruncation ?? (forceVoyageDialect ? true : null);
    return context.buildPlan(
      payload: <String, Object?>{
        ...context.textRequestFields,
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
      },
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
    final id = context.normalizedModelId;
    return baseUrl.contains('cohere') ||
        (id.startsWith('rerank-v') ||
                id.startsWith('rerank-english') ||
                id.startsWith('rerank-multilingual') ||
                id.contains('cohere-rerank')) &&
            context.profile.rerankSupportedParameters.contains(
              'max_tokens_per_doc',
            );
  }

  @override
  _RerankRequestPlan build(_RerankRequestContext context) {
    return context.buildPlan(
      payload: <String, Object?>{
        ...context.textRequestFieldsWithTopN,
        if (context.supportsParameter('max_tokens_per_doc') &&
            context.positiveMaxTokensPerDoc != null)
          'max_tokens_per_doc': context.positiveMaxTokensPerDoc,
        if (context.supportsParameter('priority') &&
            context.positivePriority != null)
          'priority': context.positivePriority,
      },
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
    return context.buildPlan(
      payload: <String, Object?>{
        'model': context.modelId,
        'query': context.query,
        'documents': context.documents,
        if (context.supportsParameter('top_n') && context.resolvedTopN != null)
          'top_n': context.resolvedTopN,
        if ((context.profile.rerankSupportsReturnDocuments ||
                context.supportsParameter('return_documents')) &&
            context.resolvedReturnDocuments != null)
          'return_documents': context.resolvedReturnDocuments,
        if (context.supportsParameter('max_chunks_per_doc') &&
            context.positiveMaxChunksPerDoc != null)
          'max_chunks_per_doc': context.positiveMaxChunksPerDoc,
        if (context.supportsParameter('max_tokens_per_doc') &&
            context.positiveMaxTokensPerDoc != null)
          'max_tokens_per_doc': context.positiveMaxTokensPerDoc,
        if (context.supportsParameter('truncation') &&
            context.resolvedTruncation != null)
          'truncation': context.resolvedTruncation,
        if (context.supportsParameter('instruct') &&
            context.resolvedInstruction != null)
          'instruct': context.resolvedInstruction,
      },
      fallbackPath:
          context.profileEndpointPath ??
          (AiOperationHttp.isSparkBaseUrl(context.model.baseUrl)
              ? 'rerank'
              : null),
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
    if (text is String && nullIfBlank(text) != null) return text;
    return jsonEncode(document);
  }
  if (document is Map) {
    final map = stringKeyedMapFromValue(document);
    final text = map['text'];
    if (text is String && nullIfBlank(text) != null) return text;
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

const Set<String> _deepMergeableRerankBodyKeys = <String>{
  'metadata',
  'parameters',
  'input',
};

String _normalizeRerankRequestModelId(AiModelConfig model, String modelId) {
  final trimmed = modelId.trim();
  final slash = trimmed.lastIndexOf('/');
  if (slash <= 0 || slash + 1 >= trimmed.length) return trimmed;
  final owner = trimmed.substring(0, slash).toLowerCase();
  final leaf = trimmed.substring(slash + 1).trim();
  final lowerLeaf = leaf.toLowerCase();
  final lowerBaseUrl = model.baseUrl.toLowerCase();
  if ((lowerBaseUrl.contains('jina.ai') ||
          owner == 'jina' ||
          owner == 'jina-ai' ||
          owner == 'jinaai') &&
      (lowerLeaf.startsWith('jina-reranker') ||
          lowerLeaf.startsWith('jina-colbert'))) {
    return leaf;
  }
  if ((lowerBaseUrl.contains('voyage.ai') ||
          lowerBaseUrl.contains('voyageai') ||
          owner == 'voyage' ||
          owner == 'voyage-ai' ||
          owner == 'voyageai') &&
      (lowerLeaf.startsWith('rerank') ||
          lowerLeaf.startsWith('voyage-rerank'))) {
    return leaf;
  }
  if ((lowerBaseUrl.contains('cohere') || owner == 'cohere') &&
      (lowerLeaf.startsWith('rerank-') ||
          lowerLeaf.startsWith('rerank_') ||
          lowerLeaf.startsWith('cohere-rerank'))) {
    return leaf;
  }
  return trimmed;
}
