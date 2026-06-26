import 'dart:async';

import '../../model/ai_api_dialect.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiEmbeddingResult {
  const AiEmbeddingResult({
    required this.vectors,
    required this.rawResponse,
    this.payload = const <String, Object?>{},
  });

  final List<List<double>> vectors;
  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiEmbeddingsService {
  AiEmbeddingsService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  static const String _geminiDefaultEmbeddingPath =
      'v1beta/models/{model_id}:embedContent';
  static const String _geminiDefaultBatchEmbeddingPath =
      'v1beta/models/{model_id}:batchEmbedContents';
  static const AiEmbeddingResult _emptyResult = AiEmbeddingResult(
    vectors: <List<double>>[],
    rawResponse: '',
    payload: <String, Object?>{'data': <Object?>[]},
  );
  static const List<_EmbeddingRequestStrategy> _requestStrategies =
      <_EmbeddingRequestStrategy>[
        _GeminiEmbeddingStrategy(),
        _DashScopeMultimodalEmbeddingStrategy(),
        _MistralEmbeddingStrategy(),
        _OpenAiCompatibleEmbeddingStrategy(),
      ];

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<AiEmbeddingResult> createEmbeddings({
    required AiModelConfig model,
    required List<String> input,
    Duration timeout = const Duration(seconds: 60),
    int? dimensions,
    String? encodingFormat,
    String? user,
  }) async {
    return createEmbedding(
      model: model,
      input: input,
      timeout: timeout,
      dimensions: dimensions,
      encodingFormat: encodingFormat,
      user: user,
    );
  }

  Future<AiEmbeddingResult> createEmbedding({
    required AiModelConfig model,
    required Object input,
    Duration timeout = const Duration(seconds: 60),
    int? dimensions,
    String? encodingFormat,
    String? user,
  }) async {
    if (input is List && input.isEmpty) return _emptyResult;
    final plan = _buildRequestPlan(
      model: model,
      input: input,
      dimensions: dimensions,
      encodingFormat: encodingFormat,
      user: user,
    );
    return _sendPlan(model: model, plan: plan, timeout: timeout);
  }

  Future<AiEmbeddingResult> _sendPlan({
    required AiModelConfig model,
    required _EmbeddingRequestPlan plan,
    required Duration timeout,
  }) async {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.embeddings,
      fallbackPath: plan.fallbackPath,
      method: model.requestMethod,
    );
    const family = AiApiFamily.embeddings;
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
    return AiEmbeddingResult(
      vectors: _parseVectors(payload),
      rawResponse: response.body,
      payload: payload,
    );
  }

  Future<AiEmbeddingResult> createEngineEmbedding({
    required AiModelConfig model,
    required Object content,
    Duration timeout = const Duration(seconds: 60),
    String taskType = '',
    String title = '',
  }) async {
    final plan = const _GeminiEmbeddingStrategy().build(
      _EmbeddingRequestContext(
        model: model,
        input: content,
        taskType: taskType,
        title: title,
        forceSingle: true,
      ),
    );
    return _sendPlan(model: model, plan: plan, timeout: timeout);
  }

  _EmbeddingRequestPlan _buildRequestPlan({
    required AiModelConfig model,
    required Object input,
    int? dimensions,
    String? encodingFormat,
    String? user,
  }) {
    final context = _EmbeddingRequestContext(
      model: model,
      input: input,
      dimensions: dimensions,
      encodingFormat: encodingFormat,
      user: user,
    );
    for (final strategy in _requestStrategies) {
      if (strategy.matches(context)) return strategy.build(context);
    }
    throw StateError('No embedding request strategy matched.');
  }

  List<List<double>> _parseVectors(Map<String, Object?> payload) {
    final vectors = <List<double>>[];

    final known = _parseKnownVectorContainers(payload);
    if (known.isNotEmpty) return known;

    void collect(Object? value) {
      if (value == null) return;
      if (value is List && value.every((item) => item is num)) {
        vectors.add(
          value
              .whereType<num>()
              .map((item) => item.toDouble())
              .toList(growable: false),
        );
        return;
      }
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      if (value is! Map) return;
      final map = Map<String, Object?>.from(value);
      for (final key in const <String>['embedding', 'values']) {
        final candidate = map[key];
        if (candidate is List) {
          collect(candidate);
        }
      }
      for (final key in const <String>[
        'data',
        'embeddings',
        'embedding',
        'output',
        'result',
        'results',
        'vectors',
      ]) {
        final nested = map[key];
        if (nested != null && !identical(nested, value)) {
          collect(nested);
        }
      }
    }

    collect(payload);
    return vectors;
  }

  List<List<double>> _parseKnownVectorContainers(Map<String, Object?> payload) {
    final vectors = <List<double>>[];
    void add(Object? value) {
      final vector = _numericVectorOrNull(value);
      if (vector != null) {
        vectors.add(vector);
      }
    }

    void addFromMap(Object? raw) {
      if (raw is! Map) return;
      final map = Map<String, Object?>.from(raw);
      add(map['embedding']);
      add(map['values']);
      add(map['vector']);
    }

    void addFromList(Object? raw) {
      if (raw is! List) return;
      for (final item in raw) {
        addFromMap(item);
        add(item);
      }
    }

    addFromMap(payload['embedding']);
    addFromList(payload['embeddings']);
    addFromList(payload['data']);
    addFromList(payload['vectors']);

    final output = payload['output'];
    if (output is Map) {
      final map = Map<String, Object?>.from(output);
      addFromMap(map['embedding']);
      addFromList(map['embeddings']);
      addFromList(map['data']);
      addFromList(map['vectors']);
    }
    return vectors;
  }

  List<double>? _numericVectorOrNull(Object? value) {
    if (value is! List ||
        value.isEmpty ||
        !value.every((item) => item is num)) {
      return null;
    }
    return value
        .whereType<num>()
        .map((item) => item.toDouble())
        .toList(growable: false);
  }

  void dispose() {
    _transport.dispose();
  }
}

class _EmbeddingRequestPlan {
  const _EmbeddingRequestPlan({
    required this.body,
    required this.contextHint,
    this.fallbackPath,
  });

  final Map<String, Object?> body;
  final String contextHint;
  final String? fallbackPath;
}

class _EmbeddingRequestContext {
  _EmbeddingRequestContext({
    required this.model,
    required this.input,
    this.dimensions,
    this.encodingFormat,
    this.user,
    this.taskType = '',
    this.title = '',
    this.forceSingle = false,
  }) : modelId = model.resolveOperationModelId(AiApiFamily.embeddings),
       profile = model.profileFor(
         model.resolveOperationModelId(AiApiFamily.embeddings),
       );

  final AiModelConfig model;
  final Object input;
  final int? dimensions;
  final String? encodingFormat;
  final String? user;
  final String taskType;
  final String title;
  final bool forceSingle;
  final String modelId;
  final AiModelProfile profile;

  int? get positiveDimensions =>
      dimensions == null || dimensions! <= 0 ? null : dimensions;
  String get normalizedModelId => modelId.toLowerCase();
  String? get trimmedEncodingFormat => _trimmedOrNull(encodingFormat);
  String? get trimmedUser => _trimmedOrNull(user);
  String? get trimmedTaskType => _trimmedOrNull(taskType);
  String? get trimmedTitle => _trimmedOrNull(title);
  String? get profileEndpointPath =>
      _trimmedOrNull(profile.embeddingEndpointPath);
}

abstract class _EmbeddingRequestStrategy {
  const _EmbeddingRequestStrategy();

  bool matches(_EmbeddingRequestContext context);

  _EmbeddingRequestPlan build(_EmbeddingRequestContext context);
}

class _OpenAiCompatibleEmbeddingStrategy extends _EmbeddingRequestStrategy {
  const _OpenAiCompatibleEmbeddingStrategy();

  @override
  bool matches(_EmbeddingRequestContext context) => true;

  @override
  _EmbeddingRequestPlan build(_EmbeddingRequestContext context) {
    const family = AiApiFamily.embeddings;
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      <String, Object?>{
        'model': context.modelId,
        'input': context.input,
        if (context.positiveDimensions != null)
          'dimensions': context.positiveDimensions,
        if (context.trimmedEncodingFormat != null)
          'encoding_format': context.trimmedEncodingFormat,
        if (context.trimmedUser != null) 'user': context.trimmedUser,
      },
    );
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath,
      contextHint: 'embeddings',
    );
  }
}

class _MistralEmbeddingStrategy extends _EmbeddingRequestStrategy {
  const _MistralEmbeddingStrategy();

  @override
  bool matches(_EmbeddingRequestContext context) {
    final baseUrl = context.model.baseUrl.toLowerCase();
    return context.normalizedModelId.startsWith('mistral-embed') ||
        context.normalizedModelId.startsWith('codestral-embed') ||
        baseUrl.contains('api.mistral.ai');
  }

  @override
  _EmbeddingRequestPlan build(_EmbeddingRequestContext context) {
    const family = AiApiFamily.embeddings;
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      <String, Object?>{
        'model': context.modelId,
        'input': context.input,
        if (context.positiveDimensions != null)
          'output_dimension': context.positiveDimensions,
      },
    );
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath,
      contextHint: 'embeddings/mistral',
    );
  }
}

class _GeminiEmbeddingStrategy extends _EmbeddingRequestStrategy {
  const _GeminiEmbeddingStrategy();

  @override
  bool matches(_EmbeddingRequestContext context) {
    return context.model.protocolType == AiProtocolType.gemini ||
        context.model.apiDialect == AiApiDialect.geminiNative;
  }

  @override
  _EmbeddingRequestPlan build(_EmbeddingRequestContext context) {
    const family = AiApiFamily.embeddings;
    final modelName = 'models/${context.modelId}';
    final textBatch = context.forceSingle
        ? null
        : _stringBatchOrNull(context.input);
    final isBatch = textBatch != null && textBatch.length > 1;
    final Map<String, Object?> body;
    if (isBatch) {
      body = <String, Object?>{
        'requests': textBatch
            .map(
              (text) => <String, Object?>{
                'model': modelName,
                'content': _geminiContentPayload(text),
                if (context.trimmedTaskType != null)
                  'taskType': context.trimmedTaskType,
                if (context.trimmedTitle != null) 'title': context.trimmedTitle,
                if (context.positiveDimensions != null)
                  'outputDimensionality': context.positiveDimensions,
              },
            )
            .toList(growable: false),
      };
    } else {
      final content = textBatch == null || textBatch.isEmpty
          ? context.input
          : textBatch.first;
      body = <String, Object?>{
        'model': modelName,
        'content': _geminiContentPayload(content),
        if (context.trimmedTaskType != null)
          'taskType': context.trimmedTaskType,
        if (context.trimmedTitle != null) 'title': context.trimmedTitle,
        if (context.positiveDimensions != null)
          'outputDimensionality': context.positiveDimensions,
      };
    }
    return _EmbeddingRequestPlan(
      body: AiOperationHttp.mergeBodyExtras(context.model, family, body),
      fallbackPath:
          context.profileEndpointPath ??
          (isBatch
              ? AiEmbeddingsService._geminiDefaultBatchEmbeddingPath
              : AiEmbeddingsService._geminiDefaultEmbeddingPath),
      contextHint: isBatch ? 'embeddings/gemini/batch' : 'embeddings/gemini',
    );
  }
}

class _DashScopeMultimodalEmbeddingStrategy extends _EmbeddingRequestStrategy {
  const _DashScopeMultimodalEmbeddingStrategy();

  static const String _fallbackPath =
      'api/v1/services/embeddings/multimodal-embedding/multimodal-embedding';

  @override
  bool matches(_EmbeddingRequestContext context) {
    final endpointPath =
        context.profile.embeddingEndpointPath?.toLowerCase() ?? '';
    return context.model.protocolType == AiProtocolType.qwen &&
        (endpointPath.contains('multimodal-embedding') ||
            context.normalizedModelId.contains('vl-embedding') ||
            context.normalizedModelId.contains('embedding-vision') ||
            context.normalizedModelId.contains('multimodal-embedding'));
  }

  @override
  _EmbeddingRequestPlan build(_EmbeddingRequestContext context) {
    const family = AiApiFamily.embeddings;
    final parameters = <String, Object?>{
      if (context.normalizedModelId.contains('vl-embedding'))
        'enable_fusion': true,
      if (context.positiveDimensions != null)
        'dimension': context.positiveDimensions,
    };
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      <String, Object?>{
        'model': context.modelId,
        'input': <String, Object?>{
          'contents': _dashScopeMultimodalContents(context.input),
        },
        if (parameters.isNotEmpty) 'parameters': parameters,
      },
    );
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath ?? _fallbackPath,
      contextHint: 'embeddings/dashscope/multimodal',
    );
  }
}

Map<String, Object?> _geminiContentPayload(Object content) {
  if (content is Map<String, Object?>) return content;
  if (content is Map) return Map<String, Object?>.from(content);
  if (content is List) {
    return <String, Object?>{'parts': content};
  }
  return <String, Object?>{
    'parts': <Map<String, Object?>>[
      <String, Object?>{'text': '$content'},
    ],
  };
}

List<Map<String, Object?>> _dashScopeMultimodalContents(Object input) {
  if (input is List) {
    if (input.length > 1) {
      throw ArgumentError(
        'DashScope multimodal embedding API only supports one fused input per request.',
      );
    }
    if (input.isEmpty) return const <Map<String, Object?>>[];
    return _dashScopeMultimodalContents(input.first);
  }
  if (input is Map<String, Object?>) return <Map<String, Object?>>[input];
  if (input is Map) {
    return <Map<String, Object?>>[Map<String, Object?>.from(input)];
  }
  return <Map<String, Object?>>[
    <String, Object?>{'text': '$input'},
  ];
}

List<String>? _stringBatchOrNull(Object input) {
  if (input is! List) return null;
  final values = <String>[];
  for (final item in input) {
    if (item is! String) return null;
    values.add(item);
  }
  return values;
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
