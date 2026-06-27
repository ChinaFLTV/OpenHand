import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
        _PerplexityContextualizedEmbeddingStrategy(),
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
      vectors: _parseVectors(
        payload,
        encodingFormat: _embeddingResponseEncoding(plan.body),
      ),
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

  List<List<double>> _parseVectors(
    Map<String, Object?> payload, {
    required String encodingFormat,
  }) {
    final vectors = <List<double>>[];

    final known = _parseKnownVectorContainers(
      payload,
      encodingFormat: encodingFormat,
    );
    if (known.isNotEmpty) return known;

    void collect(Object? value) {
      if (value == null) return;
      final vector = _vectorOrNull(value, encodingFormat: encodingFormat);
      if (vector != null) {
        vectors.add(vector);
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

  List<List<double>> _parseKnownVectorContainers(
    Map<String, Object?> payload, {
    required String encodingFormat,
  }) {
    final vectors = <List<double>>[];
    void add(Object? value) {
      final vector = _vectorOrNull(value, encodingFormat: encodingFormat);
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

  List<double>? _vectorOrNull(Object? value, {required String encodingFormat}) {
    if (value is String) {
      return _encodedVectorOrNull(value, encodingFormat: encodingFormat);
    }
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

  List<double>? _encodedVectorOrNull(
    String value, {
    required String encodingFormat,
  }) {
    final normalized = encodingFormat.trim().toLowerCase();
    if (!normalized.startsWith('base64')) return null;
    final bytes = _base64BytesOrNull(value);
    if (bytes == null || bytes.isEmpty) return null;
    if (normalized == 'base64_int8') {
      return bytes
          .map((byte) => byte >= 128 ? byte - 256 : byte)
          .map((value) => value.toDouble())
          .toList(growable: false);
    }
    if (normalized == 'base64_binary') {
      return <double>[
        for (final byte in bytes)
          for (var bit = 0; bit < 8; bit += 1) ((byte >> bit) & 1).toDouble(),
      ];
    }
    if (normalized == 'base64' || normalized == 'base64_float32') {
      if (bytes.length % 4 != 0) return null;
      final data = ByteData.sublistView(Uint8List.fromList(bytes));
      return <double>[
        for (var offset = 0; offset < bytes.length; offset += 4)
          data.getFloat32(offset, Endian.little),
      ];
    }
    return null;
  }

  List<int>? _base64BytesOrNull(String value) {
    try {
      return base64Decode(value.trim());
    } on FormatException {
      return null;
    }
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

  Map<String, Object?> withProfileDefaults(Map<String, Object?> payload) {
    final defaults = profile.defaultParameters;
    if (defaults.isEmpty) return payload;
    return _deepMergeObjectMaps(defaults, payload);
  }

  bool supportsParameter(String key) {
    final normalizedKey = key.trim().toLowerCase();
    if (normalizedKey.isEmpty) return false;
    return profile.supportedParameters.any(
      (parameter) => parameter.trim().toLowerCase() == normalizedKey,
    );
  }
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
    final payload = <String, Object?>{
      'model': context.modelId,
      'input': context.input,
      if (context.positiveDimensions != null)
        'dimensions': context.positiveDimensions,
      if (context.supportsParameter('encoding_format') &&
          context.trimmedEncodingFormat != null)
        'encoding_format': context.trimmedEncodingFormat,
      if (context.supportsParameter('input_type') &&
          context.trimmedInputType != null)
        'input_type': context.trimmedInputType,
      if (context.supportsParameter('task') && context.trimmedTaskType != null)
        'task': context.trimmedTaskType,
      if (context.supportsParameter('output_dtype') &&
          context.trimmedOutputDType != null)
        'output_dtype': context.trimmedOutputDType,
      if (context.supportsParameter('truncate') &&
          context.trimmedTruncation != null)
        'truncate': context.trimmedTruncation,
      if (context.supportsParameter('truncation') &&
          context.trimmedTruncation != null)
        'truncation': _truncationValue(context.trimmedTruncation),
      if (context.trimmedUser != null) 'user': context.trimmedUser,
    };
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      context.withProfileDefaults(payload),
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
      context.withProfileDefaults(<String, Object?>{
        'model': context.modelId,
        'input': context.input,
        if (context.positiveDimensions != null)
          'output_dimension': context.positiveDimensions,
        if (context.trimmedOutputDType != null)
          'output_dtype': context.trimmedOutputDType,
      }),
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
        context.supportsParameter('texts') &&
            context.supportsParameter('input_type');
  }

  @override
  _EmbeddingRequestPlan build(_EmbeddingRequestContext context) {
    const family = AiApiFamily.embeddings;
    final embeddingType =
        context.trimmedOutputDType ?? context.trimmedEncodingFormat;
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      context.withProfileDefaults(<String, Object?>{
        'model': context.modelId,
        'texts': _stringInputList(context.input),
        if (context.trimmedInputType != null)
          'input_type': context.trimmedInputType,
        if (embeddingType != null) 'embedding_types': <String>[embeddingType],
        if (context.trimmedTruncation != null)
          'truncate': context.trimmedTruncation,
      }),
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
      context.withProfileDefaults(<String, Object?>{
        'model': context.modelId,
        'input': context.input,
        if (context.trimmedInputType != null)
          'input_type': context.trimmedInputType,
        if (context.positiveDimensions != null)
          'output_dimension': context.positiveDimensions,
        if (context.trimmedOutputDType != null)
          'output_dtype': context.trimmedOutputDType,
        if (truncation != null) 'truncation': truncation,
      }),
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
        context.supportsParameter('embedding_type') &&
            context.supportsParameter('task');
  }

  @override
  _EmbeddingRequestPlan build(_EmbeddingRequestContext context) {
    const family = AiApiFamily.embeddings;
    final embeddingType =
        context.trimmedOutputDType ?? context.trimmedEncodingFormat;
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      context.withProfileDefaults(<String, Object?>{
        'model': context.modelId,
        'input': context.input,
        if (context.trimmedTaskType != null) 'task': context.trimmedTaskType,
        if (context.positiveDimensions != null)
          'dimensions': context.positiveDimensions,
        if (embeddingType != null) 'embedding_type': embeddingType,
        if (context.profile.embeddingOutputsNormalized != null)
          'normalized': context.profile.embeddingOutputsNormalized,
      }),
    );
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath,
      contextHint: 'embeddings/jina',
    );
  }
}

class _PerplexityContextualizedEmbeddingStrategy
    extends _EmbeddingRequestStrategy {
  const _PerplexityContextualizedEmbeddingStrategy();

  static const String _fallbackPath = 'v1/embeddings/contextualized';

  @override
  bool matches(_EmbeddingRequestContext context) {
    final endpointPath = context.profileEndpointPath?.toLowerCase() ?? '';
    return context.normalizedModelId.startsWith('pplx-embed-context') ||
        endpointPath.contains('embeddings/contextualized');
  }

  @override
  _EmbeddingRequestPlan build(_EmbeddingRequestContext context) {
    const family = AiApiFamily.embeddings;
    final payload = <String, Object?>{
      'model': context.modelId,
      'input': _perplexityContextualizedInput(context.input),
      if (context.positiveDimensions != null)
        'dimensions': context.positiveDimensions,
      if (context.supportsParameter('encoding_format') &&
          context.trimmedEncodingFormat != null)
        'encoding_format': context.trimmedEncodingFormat,
    };
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      context.withProfileDefaults(payload),
    );
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath: context.profileEndpointPath ?? _fallbackPath,
      contextHint: 'embeddings/perplexity/contextualized',
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
      body: AiOperationHttp.mergeBodyExtras(
        context.model,
        family,
        context.withProfileDefaults(body),
      ),
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
      context.withProfileDefaults(<String, Object?>{
        'model': context.modelId,
        'input': <String, Object?>{
          'contents': _dashScopeMultimodalContents(context.input),
        },
        if (parameters.isNotEmpty) 'parameters': parameters,
      }),
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

List<List<String>> _perplexityContextualizedInput(Object input) {
  if (input is List) {
    if (input.isEmpty) return const <List<String>>[];
    if (input.every((item) => item is List)) {
      return input
          .whereType<List>()
          .map(
            (document) =>
                document.map((chunk) => '$chunk').toList(growable: false),
          )
          .where((document) => document.isNotEmpty)
          .toList(growable: false);
    }
    return <List<String>>[
      input.map((chunk) => '$chunk').toList(growable: false),
    ];
  }
  return <List<String>>[
    <String>['$input'],
  ];
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

String _embeddingResponseEncoding(Map<String, Object?> body) {
  final encodingFormat = body['encoding_format'];
  if (encodingFormat is String) return encodingFormat;
  final embeddingType = body['embedding_type'];
  if (embeddingType is String) return embeddingType;
  final embeddingTypes = body['embedding_types'];
  if (embeddingTypes is List && embeddingTypes.isNotEmpty) {
    return '${embeddingTypes.first}';
  }
  return '';
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
    if (_deepMergeableEmbeddingBodyKeys.contains(entry.key) &&
        defaultMap.isNotEmpty &&
        overrideMap.isNotEmpty) {
      merged[entry.key] = _deepMergeObjectMaps(defaultMap, overrideMap);
    } else {
      merged[entry.key] = entry.value;
    }
  }
  return merged;
}

const Set<String> _deepMergeableEmbeddingBodyKeys = <String>{
  'metadata',
  'parameters',
};

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
