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
    final plan = _buildGeminiRequestPlan(
      model: model,
      input: content,
      taskType: taskType,
      title: title,
      forceSingle: true,
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
    if (_usesGeminiEmbeddingApi(model)) {
      return _buildGeminiRequestPlan(
        model: model,
        input: input,
        dimensions: dimensions,
      );
    }
    if (_usesDashScopeMultimodalEmbeddingApi(model)) {
      return _buildDashScopeMultimodalRequestPlan(
        model: model,
        input: input,
        dimensions: dimensions,
      );
    }
    if (_usesMistralEmbeddingApi(model)) {
      return _buildMistralRequestPlan(
        model: model,
        input: input,
        dimensions: dimensions,
      );
    }
    return _buildOpenAiCompatibleRequestPlan(
      model: model,
      input: input,
      dimensions: dimensions,
      encodingFormat: encodingFormat,
      user: user,
    );
  }

  _EmbeddingRequestPlan _buildDashScopeMultimodalRequestPlan({
    required AiModelConfig model,
    required Object input,
    int? dimensions,
  }) {
    const family = AiApiFamily.embeddings;
    final modelId = model.resolveOperationModelId(family);
    final profile = model.profileFor(modelId);
    final contents = _dashScopeMultimodalContents(input);
    final parameters = <String, Object?>{
      if (modelId.toLowerCase().contains('vl-embedding')) 'enable_fusion': true,
      if (dimensions != null && dimensions > 0) 'dimension': dimensions,
    };
    final body = AiOperationHttp.mergeBodyExtras(
      model,
      family,
      <String, Object?>{
        'model': modelId,
        'input': <String, Object?>{'contents': contents},
        if (parameters.isNotEmpty) 'parameters': parameters,
      },
    );
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath:
          _trimmedOrNull(profile.embeddingEndpointPath) ??
          'api/v1/services/embeddings/multimodal-embedding/multimodal-embedding',
      contextHint: 'embeddings/dashscope/multimodal',
    );
  }

  _EmbeddingRequestPlan _buildOpenAiCompatibleRequestPlan({
    required AiModelConfig model,
    required Object input,
    int? dimensions,
    String? encodingFormat,
    String? user,
  }) {
    const family = AiApiFamily.embeddings;
    final profile = model.profileFor(model.resolveOperationModelId(family));
    final body =
        AiOperationHttp.mergeBodyExtras(model, family, <String, Object?>{
          'model': model.resolveOperationModelId(family),
          'input': input,
          if (dimensions != null && dimensions > 0) 'dimensions': dimensions,
          if (encodingFormat?.trim().isNotEmpty == true)
            'encoding_format': encodingFormat!.trim(),
          if (user?.trim().isNotEmpty == true) 'user': user!.trim(),
        });
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath: _trimmedOrNull(profile.embeddingEndpointPath),
      contextHint: 'embeddings',
    );
  }

  _EmbeddingRequestPlan _buildMistralRequestPlan({
    required AiModelConfig model,
    required Object input,
    int? dimensions,
  }) {
    const family = AiApiFamily.embeddings;
    final profile = model.profileFor(model.resolveOperationModelId(family));
    final body =
        AiOperationHttp.mergeBodyExtras(model, family, <String, Object?>{
          'model': model.resolveOperationModelId(family),
          'input': input,
          if (dimensions != null && dimensions > 0)
            'output_dimension': dimensions,
        });
    return _EmbeddingRequestPlan(
      body: body,
      fallbackPath: _trimmedOrNull(profile.embeddingEndpointPath),
      contextHint: 'embeddings/mistral',
    );
  }

  _EmbeddingRequestPlan _buildGeminiRequestPlan({
    required AiModelConfig model,
    required Object input,
    int? dimensions,
    String taskType = '',
    String title = '',
    bool forceSingle = false,
  }) {
    const family = AiApiFamily.embeddings;
    final modelId = model.resolveOperationModelId(family);
    final profile = model.profileFor(modelId);
    final modelName = 'models/$modelId';
    final trimmedTaskType = taskType.trim();
    final trimmedTitle = title.trim();
    final textBatch = forceSingle ? null : _stringBatchOrNull(input);
    final isBatch = textBatch != null && textBatch.length > 1;
    final fallbackPath = _trimmedOrNull(profile.embeddingEndpointPath);
    final Map<String, Object?> body;
    if (isBatch) {
      body = <String, Object?>{
        'requests': textBatch
            .map(
              (text) => <String, Object?>{
                'model': modelName,
                'content': _geminiContentPayload(text),
                if (trimmedTaskType.isNotEmpty) 'taskType': trimmedTaskType,
                if (trimmedTitle.isNotEmpty) 'title': trimmedTitle,
                if (dimensions != null && dimensions > 0)
                  'outputDimensionality': dimensions,
              },
            )
            .toList(growable: false),
      };
    } else {
      final content = textBatch == null || textBatch.isEmpty
          ? input
          : textBatch.first;
      body = <String, Object?>{
        'model': modelName,
        'content': _geminiContentPayload(content),
        if (trimmedTaskType.isNotEmpty) 'taskType': trimmedTaskType,
        if (trimmedTitle.isNotEmpty) 'title': trimmedTitle,
        if (dimensions != null && dimensions > 0)
          'outputDimensionality': dimensions,
      };
    }
    return _EmbeddingRequestPlan(
      body: AiOperationHttp.mergeBodyExtras(model, family, body),
      fallbackPath:
          fallbackPath ??
          (isBatch
              ? _geminiDefaultBatchEmbeddingPath
              : _geminiDefaultEmbeddingPath),
      contextHint: isBatch ? 'embeddings/gemini/batch' : 'embeddings/gemini',
    );
  }

  bool _usesGeminiEmbeddingApi(AiModelConfig model) {
    return model.protocolType == AiProtocolType.gemini ||
        model.apiDialect == AiApiDialect.geminiNative;
  }

  bool _usesDashScopeMultimodalEmbeddingApi(AiModelConfig model) {
    final rawModelId = model.resolveOperationModelId(AiApiFamily.embeddings);
    final modelId = rawModelId.toLowerCase();
    final profile = model.profileFor(rawModelId);
    final endpointPath = profile.embeddingEndpointPath?.toLowerCase() ?? '';
    return model.protocolType == AiProtocolType.qwen &&
        (endpointPath.contains('multimodal-embedding') ||
            modelId.contains('vl-embedding') ||
            modelId.contains('embedding-vision') ||
            modelId.contains('multimodal-embedding'));
  }

  bool _usesMistralEmbeddingApi(AiModelConfig model) {
    final modelId = model
        .resolveOperationModelId(AiApiFamily.embeddings)
        .toLowerCase();
    final baseUrl = model.baseUrl.toLowerCase();
    return modelId.startsWith('mistral-embed') ||
        modelId.startsWith('codestral-embed') ||
        baseUrl.contains('api.mistral.ai');
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

  String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
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
