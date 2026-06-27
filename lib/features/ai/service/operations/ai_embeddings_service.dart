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
        _CohereEmbeddingStrategy(),
        _VoyageEmbeddingStrategy(),
        _JinaEmbeddingStrategy(),
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
    String? inputType,
    String? taskType,
    String? title,
    String? outputDType,
    String? truncation,
    String? user,
  }) async {
    return createEmbedding(
      model: model,
      input: input,
      timeout: timeout,
      dimensions: dimensions,
      encodingFormat: encodingFormat,
      inputType: inputType,
      taskType: taskType,
      title: title,
      outputDType: outputDType,
      truncation: truncation,
      user: user,
    );
  }

  Future<AiEmbeddingResult> createEmbedding({
    required AiModelConfig model,
    required Object input,
    Duration timeout = const Duration(seconds: 60),
    int? dimensions,
    String? encodingFormat,
    String? inputType,
    String? taskType,
    String? title,
    String? outputDType,
    String? truncation,
    String? user,
  }) async {
    if (input is List && input.isEmpty) return _emptyResult;
    final plan = _buildRequestPlan(
      model: model,
      input: input,
      dimensions: dimensions,
      encodingFormat: encodingFormat,
      inputType: inputType,
      taskType: taskType,
      title: title,
      outputDType: outputDType,
      truncation: truncation,
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
    String? inputType,
    String? taskType,
    String? title,
    String? outputDType,
    String? truncation,
    String? user,
  }) {
    final context = _EmbeddingRequestContext(
      model: model,
      input: input,
      dimensions: dimensions,
      encodingFormat: encodingFormat,
      inputType: inputType,
      taskType: taskType ?? '',
      title: title ?? '',
      outputDType: outputDType,
      truncation: truncation,
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

    void addFromEmbeddingTypeMap(Object? raw) {
      if (raw is! Map) return;
      final map = Map<String, Object?>.from(raw);
      for (final value in map.values) {
        addFromList(value);
        add(value);
      }
    }

    addFromMap(payload['embedding']);
    addFromList(payload['embeddings']);
    addFromEmbeddingTypeMap(payload['embeddings']);
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
    this.inputType,
    this.outputDType,
    this.truncation,
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
  final String? inputType;
  final String? outputDType;
  final String? truncation;
  final String? user;
  final String taskType;
  final String title;
  final bool forceSingle;
  final String modelId;
  final AiModelProfile profile;

  int? get positiveDimensions =>
      dimensions == null || dimensions! <= 0 ? null : dimensions;
  String get normalizedModelId => modelId.toLowerCase();
  String? get trimmedEncodingFormat =>
      _trimmedOrNull(encodingFormat) ??
      _trimmedOrNull(profile.embeddingDefaultEncodingFormat);
  String? get trimmedInputType =>
      _trimmedOrNull(inputType) ??
      _trimmedOrNull(profile.embeddingDefaultInputType);
  String? get trimmedOutputDType =>
      _trimmedOrNull(outputDType) ??
      _trimmedOrNull(profile.embeddingDefaultOutputDType);
  String? get trimmedTruncation =>
      _trimmedOrNull(truncation) ??
      _trimmedOrNull(profile.embeddingDefaultTruncation);
  String? get trimmedUser => _trimmedOrNull(user);
  String? get trimmedTaskType =>
      _trimmedOrNull(taskType) ??
      _trimmedOrNull(profile.embeddingDefaultTaskType);
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
        if (context.trimmedOutputDType != null)
          'output_dtype': context.trimmedOutputDType,
      },
    );
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath,
      contextHint: 'embeddings/mistral',
    );
  }
}

class _CohereEmbeddingStrategy extends _EmbeddingRequestStrategy {
  const _CohereEmbeddingStrategy();

  @override
  bool matches(_EmbeddingRequestContext context) {
    final baseUrl = context.model.baseUrl.toLowerCase();
    return baseUrl.contains('cohere') ||
        context.profile.supportedParameters.contains('texts') &&
            context.profile.supportedParameters.contains('input_type');
  }

  @override
  _EmbeddingRequestPlan build(_EmbeddingRequestContext context) {
    const family = AiApiFamily.embeddings;
    final embeddingType =
        context.trimmedOutputDType ?? context.trimmedEncodingFormat;
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      <String, Object?>{
        'model': context.modelId,
        'texts': _stringInputList(context.input),
        if (context.trimmedInputType != null)
          'input_type': context.trimmedInputType,
        if (embeddingType != null) 'embedding_types': <String>[embeddingType],
        if (context.trimmedTruncation != null)
          'truncate': context.trimmedTruncation,
      },
    );
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath,
      contextHint: 'embeddings/cohere',
    );
  }
}

class _VoyageEmbeddingStrategy extends _EmbeddingRequestStrategy {
  const _VoyageEmbeddingStrategy();

  @override
  bool matches(_EmbeddingRequestContext context) {
    final baseUrl = context.model.baseUrl.toLowerCase();
    return context.normalizedModelId.startsWith('voyage-') ||
        baseUrl.contains('voyageai') ||
        baseUrl.contains('voyage.ai');
  }

  @override
  _EmbeddingRequestPlan build(_EmbeddingRequestContext context) {
    const family = AiApiFamily.embeddings;
    final truncation = _truncationValue(context.trimmedTruncation);
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      <String, Object?>{
        'model': context.modelId,
        'input': context.input,
        if (context.trimmedInputType != null)
          'input_type': context.trimmedInputType,
        if (context.positiveDimensions != null)
          'output_dimension': context.positiveDimensions,
        if (context.trimmedOutputDType != null)
          'output_dtype': context.trimmedOutputDType,
        if (truncation != null) 'truncation': truncation,
      },
    );
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath,
      contextHint: 'embeddings/voyage',
    );
  }
}

class _JinaEmbeddingStrategy extends _EmbeddingRequestStrategy {
  const _JinaEmbeddingStrategy();

  @override
  bool matches(_EmbeddingRequestContext context) {
    final baseUrl = context.model.baseUrl.toLowerCase();
    return context.normalizedModelId.startsWith('jina-') ||
        baseUrl.contains('jina.ai') ||
        context.profile.supportedParameters.contains('embedding_type') &&
            context.profile.supportedParameters.contains('task');
  }

  @override
  _EmbeddingRequestPlan build(_EmbeddingRequestContext context) {
    const family = AiApiFamily.embeddings;
    final embeddingType =
        context.trimmedOutputDType ?? context.trimmedEncodingFormat;
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      <String, Object?>{
        'model': context.modelId,
        'input': context.input,
        if (context.trimmedTaskType != null) 'task': context.trimmedTaskType,
        if (context.positiveDimensions != null)
          'dimensions': context.positiveDimensions,
        if (embeddingType != null) 'embedding_type': embeddingType,
        if (context.profile.embeddingOutputsNormalized != null)
          'normalized': context.profile.embeddingOutputsNormalized,
      },
    );
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath,
      contextHint: 'embeddings/jina',
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

List<String> _stringInputList(Object input) {
  if (input is List) {
    return input.map((item) => '$item').toList(growable: false);
  }
  return <String>['$input'];
}

Object? _truncationValue(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) return null;
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return value!.trim();
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
