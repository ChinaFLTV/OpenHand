import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../../shared/util/input_value_parsing.dart';
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
      _transport = transport ?? AiTransportClient(),
      _ownsTransport = transport == null;

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
        _BedrockTitanEmbeddingStrategy(),
        _CohereEmbeddingStrategy(),
        _VoyageEmbeddingStrategy(),
        _JinaEmbeddingStrategy(),
        _MistralEmbeddingStrategy(),
        _PerplexityContextualizedEmbeddingStrategy(),
        _OpenAiCompatibleEmbeddingStrategy(),
      ];

  final AiEndpointRouter _router;
  final AiTransportClient _transport;
  final bool _ownsTransport;

  Future<AiEmbeddingResult> createEmbeddings({
    required AiModelConfig model,
    required List<String> input,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
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
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
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
    final response = await AiOperationHttp.sendJsonForFamily(
      transport: _transport,
      endpoint: endpoint,
      model: model,
      family: family,
      body: plan.body,
      timeout: timeout,
    );
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: plan.contextHint,
    );
    return AiEmbeddingResult(
      vectors: _parseVectors(
        payload,
        encodingFormat: _embeddingResponseEncoding(plan.body),
        expectedDimensions:
            plan.expectedDimensions ?? _embeddingResponseDimensions(plan.body),
      ),
      rawResponse: response.body,
      payload: payload,
    );
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
    required int? expectedDimensions,
  }) {
    final vectors = <List<double>>[];

    final known = _parseKnownVectorContainers(
      payload,
      encodingFormat: encodingFormat,
      expectedDimensions: expectedDimensions,
    );
    if (known.isNotEmpty) return known;

    void collect(Object? value) {
      if (value == null) return;
      final vector = _vectorOrNull(
        value,
        encodingFormat: encodingFormat,
        expectedDimensions: expectedDimensions,
      );
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
      final map = AiOperationHttp.stringKeyedMap(value);
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
    required int? expectedDimensions,
  }) {
    final vectors = <List<double>>[];
    void add(Object? value) {
      final vector = _vectorOrNull(
        value,
        encodingFormat: encodingFormat,
        expectedDimensions: expectedDimensions,
      );
      if (vector != null) {
        vectors.add(vector);
      }
    }

    void addFromMap(Object? raw) {
      if (raw is! Map) return;
      final map = AiOperationHttp.stringKeyedMap(raw);
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
      final map = AiOperationHttp.stringKeyedMap(raw);
      final preferredKey = _preferredEmbeddingTypeKey(encodingFormat);
      if (preferredKey.isNotEmpty && map.containsKey(preferredKey)) {
        final value = map[preferredKey];
        addFromList(value);
        add(value);
        return;
      }
      for (final value in map.values) {
        addFromList(value);
        add(value);
      }
    }

    add(payload['embedding']);
    addFromMap(payload['embedding']);
    addFromList(payload['embeddings']);
    addFromEmbeddingTypeMap(payload['embeddings']);
    addFromEmbeddingTypeMap(payload['embeddingsByType']);
    addFromList(payload['data']);
    addFromList(payload['vectors']);

    final output = payload['output'];
    if (output is Map) {
      final map = AiOperationHttp.stringKeyedMap(output);
      addFromMap(map['embedding']);
      addFromList(map['embeddings']);
      addFromEmbeddingTypeMap(map['embeddings']);
      addFromEmbeddingTypeMap(map['embeddingsByType']);
      addFromList(map['data']);
      addFromList(map['vectors']);
    }
    return vectors;
  }

  List<double>? _vectorOrNull(
    Object? value, {
    required String encodingFormat,
    required int? expectedDimensions,
  }) {
    if (value is String) {
      return _encodedVectorOrNull(
        value,
        encodingFormat: encodingFormat,
        expectedDimensions: expectedDimensions,
      );
    }
    if (value is! List ||
        value.isEmpty ||
        !value.every((item) => item is num)) {
      return null;
    }
    final vector = value
        .whereType<num>()
        .map((item) => item.toDouble())
        .toList(growable: false);
    final unpacked = _unpackedBitVectorOrNull(
      vector,
      encodingFormat: encodingFormat,
      expectedDimensions: expectedDimensions,
    );
    if (unpacked != null) return unpacked;
    if (expectedDimensions == null ||
        expectedDimensions <= 0 ||
        expectedDimensions >= vector.length) {
      return vector;
    }
    return vector.sublist(0, expectedDimensions);
  }

  List<double>? _encodedVectorOrNull(
    String value, {
    required String encodingFormat,
    required int? expectedDimensions,
  }) {
    final normalized = lowercaseStringFromValue(encodingFormat);
    if (!normalized.startsWith('base64')) return null;
    final bytes = _base64BytesOrNull(value);
    if (bytes == null || bytes.isEmpty) return null;
    if (normalized == 'base64_int8') {
      return bytes
          .map((byte) => byte >= 128 ? byte - 256 : byte)
          .map((value) => value.toDouble())
          .toList(growable: false);
    }
    if (normalized == 'base64_uint8') {
      return bytes.map((byte) => byte.toDouble()).toList(growable: false);
    }
    if (normalized == 'base64_binary' || normalized == 'base64_ubinary') {
      return _unpackBitBytes(bytes, expectedDimensions: expectedDimensions);
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

  List<double>? _unpackedBitVectorOrNull(
    List<double> vector, {
    required String encodingFormat,
    required int? expectedDimensions,
  }) {
    final normalized = lowercaseStringFromValue(encodingFormat);
    if (normalized != 'binary' && normalized != 'ubinary') return null;
    if (expectedDimensions == null || expectedDimensions <= vector.length) {
      return null;
    }
    final bytes = <int>[];
    for (final item in vector) {
      final rounded = item.round();
      if (item != rounded || rounded < -128 || rounded > 255) return null;
      bytes.add(rounded & 0xff);
    }
    return _unpackBitBytes(bytes, expectedDimensions: expectedDimensions);
  }

  List<double> _unpackBitBytes(
    Iterable<int> bytes, {
    required int? expectedDimensions,
  }) {
    final vector = <double>[
      for (final byte in bytes)
        for (var bit = 0; bit < 8; bit += 1) ((byte >> bit) & 1).toDouble(),
    ];
    if (expectedDimensions == null ||
        expectedDimensions <= 0 ||
        expectedDimensions >= vector.length) {
      return vector;
    }
    return vector.sublist(0, expectedDimensions);
  }

  List<int>? _base64BytesOrNull(String value) {
    try {
      return base64Decode(value.trim());
    } on FormatException {
      return null;
    }
  }

  void dispose() {
    if (_ownsTransport) {
      _transport.dispose();
    }
  }
}

class _EmbeddingRequestPlan {
  const _EmbeddingRequestPlan({
    required this.body,
    required this.contextHint,
    this.expectedDimensions,
    this.fallbackPath,
  });

  final Map<String, Object?> body;
  final String contextHint;
  final int? expectedDimensions;
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
  final String modelId;
  final AiModelProfile profile;

  int? get positiveDimensions => optionalPositiveIntFromValue(dimensions);
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
  bool get shouldConstrainDimensions =>
      positiveDimensions != null &&
      (profile.embeddingSupportsCustomDimensions ||
          supportsParameter('dimensions') ||
          supportsParameter('output_dimension') ||
          supportsParameter('outputDimensionality') ||
          supportsParameter('embeddingConfig.outputEmbeddingLength') ||
          supportsParameter('parameters.dimension'));

  Map<String, Object?> withProfileDefaults(Map<String, Object?> payload) {
    final defaults = profile.defaultParameters;
    if (defaults.isEmpty) return payload;
    return _deepMergeObjectMaps(defaults, payload);
  }

  bool supportsParameter(String key) {
    final normalizedKey = lowercaseStringFromValue(key);
    if (normalizedKey.isEmpty) return false;
    return profile.supportedParameters.any(
      (parameter) => lowercaseStringFromValue(parameter) == normalizedKey,
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
      if (context.supportsParameter('dimensions') &&
          context.positiveDimensions != null)
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
      if (context.supportsParameter('user') && context.trimmedUser != null)
        'user': context.trimmedUser,
    };
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      context.withProfileDefaults(payload),
    );
    return _EmbeddingRequestPlan(
      body: body,
      expectedDimensions: context.shouldConstrainDimensions
          ? context.positiveDimensions
          : null,
      fallbackPath:
          context.profileEndpointPath ??
          (_isSparkBaseUrl(context.model.baseUrl) ? 'embeddings' : null),
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
        if (context.supportsParameter('output_dimension') &&
            context.positiveDimensions != null)
          'output_dimension': context.positiveDimensions,
        if (context.supportsParameter('output_dtype') &&
            context.trimmedOutputDType != null)
          'output_dtype': context.trimmedOutputDType,
      }),
    );
    return _EmbeddingRequestPlan(
      body: body,
      expectedDimensions: context.shouldConstrainDimensions
          ? context.positiveDimensions
          : null,
      fallbackPath: context.profileEndpointPath,
      contextHint: 'embeddings/mistral',
    );
  }
}

class _BedrockTitanEmbeddingStrategy extends _EmbeddingRequestStrategy {
  const _BedrockTitanEmbeddingStrategy();

  static const String _fallbackPath = 'model/{model_id}/invoke';

  @override
  bool matches(_EmbeddingRequestContext context) {
    final baseUrl = context.model.baseUrl.toLowerCase();
    return context.normalizedModelId.contains('titan-embed') &&
        (baseUrl.contains('bedrock-runtime') ||
            baseUrl.contains('bedrock.amazonaws') ||
            baseUrl.contains('amazonaws.com/bedrock'));
  }

  @override
  _EmbeddingRequestPlan build(_EmbeddingRequestContext context) {
    const family = AiApiFamily.embeddings;
    final payload = context.normalizedModelId.contains('titan-embed-image')
        ? _bedrockTitanImagePayload(context)
        : _bedrockTitanTextPayload(context);
    final body = AiOperationHttp.mergeBodyExtras(
      context.model,
      family,
      context.withProfileDefaults(payload),
    );
    return _EmbeddingRequestPlan(
      body: body,
      expectedDimensions: context.shouldConstrainDimensions
          ? context.positiveDimensions
          : null,
      fallbackPath: context.profileEndpointPath ?? _fallbackPath,
      contextHint: 'embeddings/bedrock/titan',
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
        ..._cohereInputPayload(context),
        if (context.supportsParameter('input_type') &&
            context.trimmedInputType != null)
          'input_type': context.trimmedInputType,
        if (context.supportsParameter('embedding_types') &&
            embeddingType != null)
          'embedding_types': <String>[embeddingType],
        if (context.supportsParameter('output_dimension') &&
            context.positiveDimensions != null)
          'output_dimension': context.positiveDimensions,
        if (context.supportsParameter('truncate') &&
            context.trimmedTruncation != null)
          'truncate': context.trimmedTruncation,
      }),
    );
    return _EmbeddingRequestPlan(
      body: body,
      expectedDimensions: context.shouldConstrainDimensions
          ? context.positiveDimensions
          : null,
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
        if (context.supportsParameter('input_type') &&
            context.trimmedInputType != null)
          'input_type': context.trimmedInputType,
        if (context.supportsParameter('encoding_format') &&
            context.trimmedEncodingFormat != null)
          'encoding_format': context.trimmedEncodingFormat,
        if (context.supportsParameter('output_dimension') &&
            context.positiveDimensions != null)
          'output_dimension': context.positiveDimensions,
        if (context.supportsParameter('output_dtype') &&
            context.trimmedOutputDType != null)
          'output_dtype': context.trimmedOutputDType,
        if (context.supportsParameter('truncation') && truncation != null)
          'truncation': truncation,
      }),
    );
    return _EmbeddingRequestPlan(
      body: body,
      expectedDimensions: context.shouldConstrainDimensions
          ? context.positiveDimensions
          : null,
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
        if (context.supportsParameter('task') &&
            context.trimmedTaskType != null)
          'task': context.trimmedTaskType,
        if (context.supportsParameter('dimensions') &&
            context.positiveDimensions != null)
          'dimensions': context.positiveDimensions,
        if (context.supportsParameter('embedding_type') &&
            embeddingType != null)
          'embedding_type': embeddingType,
        if (context.supportsParameter('normalized') &&
            context.profile.embeddingOutputsNormalized != null)
          'normalized': context.profile.embeddingOutputsNormalized,
        if (context.supportsParameter('truncate') &&
            context.trimmedTruncation != null)
          'truncate': _truncationValue(context.trimmedTruncation),
      }),
    );
    return _EmbeddingRequestPlan(
      body: body,
      expectedDimensions: context.shouldConstrainDimensions
          ? context.positiveDimensions
          : null,
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
      if (context.supportsParameter('dimensions') &&
          context.positiveDimensions != null)
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
      expectedDimensions: context.shouldConstrainDimensions
          ? context.positiveDimensions
          : null,
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
    final textBatch = _stringBatchOrNull(context.input);
    final isBatch = textBatch != null && textBatch.length > 1;
    final Map<String, Object?> body;
    if (isBatch) {
      body = <String, Object?>{
        'requests': textBatch
            .map(
              (text) => <String, Object?>{
                'model': modelName,
                'content': _geminiContentPayload(text),
                if (context.supportsParameter('taskType') &&
                    context.trimmedTaskType != null)
                  'taskType': context.trimmedTaskType,
                if (context.supportsParameter('title') &&
                    context.trimmedTitle != null)
                  'title': context.trimmedTitle,
                if (context.supportsParameter('outputDimensionality') &&
                    context.positiveDimensions != null)
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
        if (context.supportsParameter('taskType') &&
            context.trimmedTaskType != null)
          'taskType': context.trimmedTaskType,
        if (context.supportsParameter('title') && context.trimmedTitle != null)
          'title': context.trimmedTitle,
        if (context.supportsParameter('outputDimensionality') &&
            context.positiveDimensions != null)
          'outputDimensionality': context.positiveDimensions,
      };
    }
    return _EmbeddingRequestPlan(
      body: AiOperationHttp.mergeBodyExtras(
        context.model,
        family,
        context.withProfileDefaults(body),
      ),
      expectedDimensions: context.shouldConstrainDimensions
          ? context.positiveDimensions
          : null,
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
      if (context.supportsParameter('parameters.enable_fusion') &&
          context.normalizedModelId.contains('vl-embedding'))
        'enable_fusion': true,
      if (context.supportsParameter('parameters.dimension') &&
          context.positiveDimensions != null)
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
      expectedDimensions: context.shouldConstrainDimensions
          ? context.positiveDimensions
          : null,
      fallbackPath: context.profileEndpointPath ?? _fallbackPath,
      contextHint: 'embeddings/dashscope/multimodal',
    );
  }
}

Map<String, Object?> _bedrockTitanTextPayload(
  _EmbeddingRequestContext context,
) {
  final outputDType = context.trimmedOutputDType;
  return <String, Object?>{
    'inputText': _singleTextInput(
      context.input,
      provider: 'Amazon Bedrock Titan text embedding',
    ),
    if (context.supportsParameter('dimensions') &&
        context.positiveDimensions != null)
      'dimensions': context.positiveDimensions,
    if (context.supportsParameter('normalize') &&
        context.profile.embeddingOutputsNormalized != null)
      'normalize': context.profile.embeddingOutputsNormalized,
    if (context.supportsParameter('embeddingTypes') && outputDType != null)
      'embeddingTypes': <String>[outputDType],
  };
}

Map<String, Object?> _bedrockTitanImagePayload(
  _EmbeddingRequestContext context,
) {
  final rawMap = AiOperationHttp.stringKeyedMap(context.input);
  final payload = rawMap.isEmpty
      ? <String, Object?>{
          'inputText': _singleTextInput(
            context.input,
            provider: 'Amazon Bedrock Titan multimodal embedding',
          ),
        }
      : <String, Object?>{
          if (rawMap['inputText'] != null) 'inputText': rawMap['inputText'],
          if (rawMap['inputImage'] != null) 'inputImage': rawMap['inputImage'],
        };
  final embeddingConfig = AiOperationHttp.stringKeyedMap(
    rawMap['embeddingConfig'],
  );
  if (context.supportsParameter('embeddingConfig.outputEmbeddingLength') &&
      context.positiveDimensions != null) {
    payload['embeddingConfig'] = <String, Object?>{
      ...embeddingConfig,
      'outputEmbeddingLength': context.positiveDimensions,
    };
  } else if (embeddingConfig.isNotEmpty) {
    payload['embeddingConfig'] = embeddingConfig;
  }
  return payload;
}

Map<String, Object?> _geminiContentPayload(Object content) {
  if (content is Map<String, Object?>) return content;
  if (content is Map) return AiOperationHttp.stringKeyedMap(content);
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
    return <Map<String, Object?>>[AiOperationHttp.stringKeyedMap(input)];
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

Map<String, Object?> _cohereInputPayload(_EmbeddingRequestContext context) {
  final structuredInputs = context.supportsParameter('inputs')
      ? _cohereStructuredInputsOrNull(context.input)
      : null;
  if (structuredInputs != null) {
    return <String, Object?>{'inputs': structuredInputs};
  }
  final inputType = context.trimmedInputType?.toLowerCase();
  if (inputType == 'image' && context.supportsParameter('images')) {
    return <String, Object?>{'images': _stringInputList(context.input)};
  }
  return <String, Object?>{'texts': _stringInputList(context.input)};
}

List<Map<String, Object?>>? _cohereStructuredInputsOrNull(Object input) {
  if (input is Map<String, Object?>) {
    return _isCohereStructuredInput(input)
        ? <Map<String, Object?>>[input]
        : null;
  }
  if (input is Map) {
    final map = AiOperationHttp.stringKeyedMap(input);
    return _isCohereStructuredInput(map) ? <Map<String, Object?>>[map] : null;
  }
  if (input is! List) return null;
  final inputs = <Map<String, Object?>>[];
  for (final item in input) {
    if (item is Map<String, Object?>) {
      if (!_isCohereStructuredInput(item)) return null;
      inputs.add(item);
      continue;
    }
    if (item is Map) {
      final map = AiOperationHttp.stringKeyedMap(item);
      if (!_isCohereStructuredInput(map)) return null;
      inputs.add(map);
      continue;
    }
    return null;
  }
  return inputs;
}

bool _isCohereStructuredInput(Map<String, Object?> value) {
  final content = value['content'];
  return content is List && content.isNotEmpty;
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

String _singleTextInput(Object input, {required String provider}) {
  if (input is List) {
    if (input.length != 1) {
      throw ArgumentError('$provider API only supports one input per request.');
    }
    return '${input.single}';
  }
  return '$input';
}

Object? _truncationValue(String? value) {
  final normalized = optionalLowercaseStringFromValue(value) ?? '';
  if (normalized.isEmpty) return null;
  final parsedBool = optionalBoolFromValue(normalized);
  if (parsedBool != null) return parsedBool;
  return value!.trim();
}

String _embeddingResponseEncoding(Map<String, Object?> body) {
  final encodingFormat = body['encoding_format'];
  if (encodingFormat is String) {
    return _combinedBase64ResponseEncoding(encodingFormat, body);
  }
  final embeddingType = body['embedding_type'];
  if (embeddingType is String) return embeddingType;
  final embeddingTypes = body['embedding_types'];
  if (embeddingTypes is List && embeddingTypes.isNotEmpty) {
    return '${embeddingTypes.first}';
  }
  final camelEmbeddingTypes = body['embeddingTypes'];
  if (camelEmbeddingTypes is List && camelEmbeddingTypes.isNotEmpty) {
    return '${camelEmbeddingTypes.first}';
  }
  final outputDType = body['output_dtype'];
  if (outputDType is String) return outputDType;
  return '';
}

String _preferredEmbeddingTypeKey(String encodingFormat) {
  final normalized = lowercaseStringFromValue(encodingFormat);
  if (normalized.isEmpty) return '';
  if (normalized.startsWith('base64_')) {
    return normalized.substring('base64_'.length);
  }
  if (normalized == 'base64' || normalized == 'base64_float32') {
    return 'float';
  }
  return normalized;
}

String _combinedBase64ResponseEncoding(
  String encodingFormat,
  Map<String, Object?> body,
) {
  final normalized = lowercaseStringFromValue(encodingFormat);
  if (normalized != 'base64') return encodingFormat;
  final dtype = _embeddingResponseDType(body);
  return switch (dtype) {
    'int8' => 'base64_int8',
    'uint8' => 'base64_uint8',
    'binary' => 'base64_binary',
    'ubinary' => 'base64_ubinary',
    'float' || 'float32' => 'base64_float32',
    _ => encodingFormat,
  };
}

String _embeddingResponseDType(Map<String, Object?> body) {
  final outputDType = body['output_dtype'];
  if (outputDType is String) return lowercaseStringFromValue(outputDType);
  final embeddingType = body['embedding_type'];
  if (embeddingType is String) return lowercaseStringFromValue(embeddingType);
  final embeddingTypes = body['embedding_types'];
  if (embeddingTypes is List && embeddingTypes.isNotEmpty) {
    return lowercaseStringFromValue(embeddingTypes.first);
  }
  final camelEmbeddingTypes = body['embeddingTypes'];
  if (camelEmbeddingTypes is List && camelEmbeddingTypes.isNotEmpty) {
    return lowercaseStringFromValue(camelEmbeddingTypes.first);
  }
  return '';
}

int? _embeddingResponseDimensions(Map<String, Object?> body) {
  for (final key in const <String>[
    'dimensions',
    'output_dimension',
    'outputDimensionality',
  ]) {
    final value = optionalPositiveIntFromValue(body[key]);
    if (value != null) return value;
  }
  final parameters = AiOperationHttp.stringKeyedMap(body['parameters']);
  final dashScopeDimensions = optionalPositiveIntFromValue(
    parameters['dimension'],
  );
  if (dashScopeDimensions != null) return dashScopeDimensions;
  final embeddingConfig = AiOperationHttp.stringKeyedMap(
    body['embeddingConfig'],
  );
  return optionalPositiveIntFromValue(embeddingConfig['outputEmbeddingLength']);
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
  return nullIfBlank(value);
}

bool _isSparkBaseUrl(String baseUrl) {
  final normalized = baseUrl.toLowerCase();
  return normalized.contains('xf-yun.com') ||
      normalized.contains('xfyun') ||
      normalized.contains('xunfei');
}
