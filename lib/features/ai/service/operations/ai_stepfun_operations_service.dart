import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../chat/ai_protocol_adapter.dart';
import '../chat/ai_sse_data_parser.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import '../session_io/ai_token_usage_parser.dart';
import 'ai_operation_http.dart';

class AiStepFunPayloadResult {
  const AiStepFunPayloadResult({
    required this.rawResponse,
    this.payload = const <String, Object?>{},
  });

  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiStepFunTokenCountResult {
  const AiStepFunTokenCountResult({
    required this.totalTokens,
    required this.rawResponse,
    this.payload = const <String, Object?>{},
  });

  final int? totalTokens;
  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiStepFunSearchResult {
  const AiStepFunSearchResult({
    required this.query,
    required this.results,
    required this.rawResponse,
    this.payload = const <String, Object?>{},
  });

  final String query;
  final List<Map<String, Object?>> results;
  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiStepFunAsrSubmitResult {
  const AiStepFunAsrSubmitResult({
    required this.taskId,
    required this.rawResponse,
    this.payload = const <String, Object?>{},
  });

  final String taskId;
  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiStepFunAsrSseEvent {
  const AiStepFunAsrSseEvent({required this.type, required this.payload});

  final String type;
  final Map<String, Object?> payload;

  String get delta => '${payload['delta'] ?? ''}';
}

class AiStepFunAsrSseResponse {
  const AiStepFunAsrSseResponse({
    required this.events,
    required this.result,
    required this.rawResponse,
  });

  final List<AiStepFunAsrSseEvent> events;
  final String result;
  final String rawResponse;
}

class AiStepFunOperationsService {
  AiStepFunOperationsService({
    AiEndpointRouter? router,
    AiTransportClient? transport,
  }) : _router = router ?? const AiEndpointRouter(),
       _transport = transport ?? AiTransportClient();

  static const String _messagesCountTokensPath = 'v1/messages/count_tokens';
  static const String _asrQueryPath = 'v1/audio/asr/file/query';

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

  Future<AiStepFunTokenCountResult> countChatTokens({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    final body = await adapter.buildBody(model, messages);
    return countTokensFromBody(
      model: model,
      body: <String, Object?>{
        'model': model.resolveOperationModelId(AiApiFamily.tokenCount),
        'messages': body['messages'],
      },
      timeout: timeout,
    );
  }

  Future<AiStepFunTokenCountResult> countTokensFromBody({
    required AiModelConfig model,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    const family = AiApiFamily.tokenCount;
    final response = await _sendJson(
      model: model,
      family: family,
      body: body,
      timeout: timeout,
      contextHint: 'stepfun/token-count',
    );
    final total = _readNestedInt(response.payload, const <String>[
      'data',
      'total_tokens',
    ]);
    return AiStepFunTokenCountResult(
      totalTokens: total ?? _readInt(response.payload['input_tokens']),
      rawResponse: response.rawResponse,
      payload: response.payload,
    );
  }

  Future<AiStepFunTokenCountResult> countMessagesTokens({
    required AiModelConfig model,
    required List<Map<String, Object?>> messages,
    String? system,
    Object? tools,
    Object? outputConfig,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (messages.isEmpty) {
      throw ArgumentError.value(
        messages,
        'messages',
        'StepFun messages are empty.',
      );
    }
    final response = await _sendJson(
      model: model,
      family: AiApiFamily.messages,
      fallbackPath: _messagesCountTokensPath,
      body: <String, Object?>{
        'model': model.resolveOperationModelId(AiApiFamily.messages),
        'messages': messages,
        if (system?.trim().isNotEmpty == true) 'system': system!.trim(),
        if (tools != null) 'tools': tools,
        if (outputConfig != null) 'output_config': outputConfig,
      },
      timeout: timeout,
      contextHint: 'stepfun/messages/count-tokens',
    );
    return AiStepFunTokenCountResult(
      totalTokens: _readInt(response.payload['input_tokens']),
      rawResponse: response.rawResponse,
      payload: response.payload,
    );
  }

  Future<AiStepFunSearchResult> search({
    required AiModelConfig model,
    required String query,
    int? count,
    String? category,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    const family = AiApiFamily.search;
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      throw ArgumentError.value(
        query,
        'query',
        'StepFun search query is empty.',
      );
    }
    final response = await _sendJson(
      model: model,
      family: family,
      body: <String, Object?>{
        'query': trimmedQuery,
        if (count != null && count > 0) 'n': count.clamp(1, 20),
        if (category?.trim().isNotEmpty == true) 'category': category!.trim(),
      },
      timeout: timeout,
      contextHint: 'stepfun/search',
    );
    final results = _mapList(response.payload['results']);
    return AiStepFunSearchResult(
      query: '${response.payload['query'] ?? trimmedQuery}',
      results: results,
      rawResponse: response.rawResponse,
      payload: response.payload,
    );
  }

  Future<AiStepFunPayloadResult> createVectorStore({
    required AiModelConfig model,
    required String name,
    String type = 'text',
    Duration timeout = const Duration(seconds: 60),
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'StepFun vector store name is empty.',
      );
    }
    return _sendJson(
      model: model,
      family: AiApiFamily.vectorStores,
      body: <String, Object?>{
        'name': trimmedName,
        if (type.trim().isNotEmpty) 'type': type.trim(),
      },
      timeout: timeout,
      contextHint: 'stepfun/vector-stores/create',
    );
  }

  Future<AiStepFunPayloadResult> listVectorStores({
    required AiModelConfig model,
    int? limit,
    String? order,
    String? before,
    String? after,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return _sendJsonless(
      model: model,
      family: AiApiFamily.vectorStores,
      method: 'GET',
      query: _paginationQuery(
        limit: limit,
        order: order,
        before: before,
        after: after,
      ),
      timeout: timeout,
      contextHint: 'stepfun/vector-stores/list',
    );
  }

  Future<AiStepFunPayloadResult> retrieveVectorStore({
    required AiModelConfig model,
    required String vectorStoreId,
    Duration timeout = const Duration(seconds: 60),
  }) {
    _checkRequiredId(vectorStoreId, 'vectorStoreId');
    return _sendJsonless(
      model: model,
      family: AiApiFamily.vectorStores,
      method: 'GET',
      fallbackPath: 'v1/vector_stores/${Uri.encodeComponent(vectorStoreId)}',
      timeout: timeout,
      contextHint: 'stepfun/vector-stores/retrieve',
    );
  }

  Future<AiStepFunPayloadResult> deleteVectorStore({
    required AiModelConfig model,
    required String vectorStoreId,
    Duration timeout = const Duration(seconds: 60),
  }) {
    _checkRequiredId(vectorStoreId, 'vectorStoreId');
    return _sendJsonless(
      model: model,
      family: AiApiFamily.vectorStores,
      method: 'DELETE',
      fallbackPath: 'v1/vector_stores/${Uri.encodeComponent(vectorStoreId)}',
      timeout: timeout,
      contextHint: 'stepfun/vector-stores/delete',
    );
  }

  Future<AiStepFunPayloadResult> addVectorStoreFiles({
    required AiModelConfig model,
    required String vectorStoreId,
    required List<Map<String, Object?>> files,
    Duration timeout = const Duration(seconds: 60),
  }) {
    _checkRequiredId(vectorStoreId, 'vectorStoreId');
    if (files.isEmpty) {
      throw ArgumentError.value(
        files,
        'files',
        'StepFun vector store files are empty.',
      );
    }
    return _sendJson(
      model: model,
      family: AiApiFamily.vectorStoreFiles,
      fallbackPath:
          'v1/vector_stores/${Uri.encodeComponent(vectorStoreId)}/files',
      body: <String, Object?>{'files': files},
      timeout: timeout,
      contextHint: 'stepfun/vector-store-files/create',
    );
  }

  Future<AiStepFunPayloadResult> listVectorStoreFiles({
    required AiModelConfig model,
    required String vectorStoreId,
    int? limit,
    String? order,
    String? before,
    String? after,
    Duration timeout = const Duration(seconds: 60),
  }) {
    _checkRequiredId(vectorStoreId, 'vectorStoreId');
    return _sendJsonless(
      model: model,
      family: AiApiFamily.vectorStoreFiles,
      method: 'GET',
      fallbackPath:
          'v1/vector_stores/${Uri.encodeComponent(vectorStoreId)}/files',
      query: _paginationQuery(
        limit: limit,
        order: order,
        before: before,
        after: after,
      ),
      timeout: timeout,
      contextHint: 'stepfun/vector-store-files/list',
    );
  }

  Future<AiStepFunPayloadResult> deleteVectorStoreFile({
    required AiModelConfig model,
    required String vectorStoreId,
    required String fileId,
    Duration timeout = const Duration(seconds: 60),
  }) {
    _checkRequiredId(vectorStoreId, 'vectorStoreId');
    _checkRequiredId(fileId, 'fileId');
    return _sendJsonless(
      model: model,
      family: AiApiFamily.vectorStoreFiles,
      method: 'DELETE',
      fallbackPath:
          'v1/vector_stores/${Uri.encodeComponent(vectorStoreId)}/files/${Uri.encodeComponent(fileId)}',
      timeout: timeout,
      contextHint: 'stepfun/vector-store-files/delete',
    );
  }

  Future<AiStepFunPayloadResult> createVoice({
    required AiModelConfig model,
    required String fileId,
    String? text,
    Duration timeout = const Duration(seconds: 120),
  }) {
    final trimmedFileId = fileId.trim();
    if (trimmedFileId.isEmpty) {
      throw ArgumentError.value(
        fileId,
        'fileId',
        'StepFun voice file id is empty.',
      );
    }
    const family = AiApiFamily.audioVoices;
    return _sendJson(
      model: model,
      family: family,
      body: <String, Object?>{
        'model': model.resolveOperationModelId(family),
        'file_id': trimmedFileId,
        if (text?.trim().isNotEmpty == true) 'text': text!.trim(),
      },
      timeout: timeout,
      contextHint: 'stepfun/audio/voices/create',
    );
  }

  Future<AiStepFunPayloadResult> listVoices({
    required AiModelConfig model,
    int? limit,
    String? order,
    String? before,
    String? after,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return _sendJsonless(
      model: model,
      family: AiApiFamily.audioVoices,
      method: 'GET',
      query: _paginationQuery(
        limit: limit,
        order: order,
        before: before,
        after: after,
      ),
      timeout: timeout,
      contextHint: 'stepfun/audio/voices/list',
    );
  }

  Future<AiStepFunPayloadResult> listSystemVoices({
    required AiModelConfig model,
    String? voiceModel,
    Duration timeout = const Duration(seconds: 60),
  }) {
    const family = AiApiFamily.audioSystemVoices;
    return _sendJsonless(
      model: model,
      family: family,
      method: 'GET',
      query: <String, String>{
        'model': (voiceModel?.trim().isNotEmpty == true
            ? voiceModel!.trim()
            : model.resolveOperationModelId(family)),
      },
      timeout: timeout,
      contextHint: 'stepfun/audio/system-voices',
    );
  }

  Future<AiStepFunPayloadResult> previewVoice({
    required AiModelConfig model,
    required String fileId,
    required String sampleText,
    String? text,
    String? responseFormat,
    double? speed,
    double? volume,
    Object? voiceLabel,
    String? instruction,
    int? sampleRate,
    Object? pronunciationMap,
    bool? markdownFilter,
    Duration timeout = const Duration(seconds: 120),
  }) {
    final trimmedFileId = fileId.trim();
    final trimmedSampleText = sampleText.trim();
    if (trimmedFileId.isEmpty) {
      throw ArgumentError.value(
        fileId,
        'fileId',
        'StepFun voice file id is empty.',
      );
    }
    if (trimmedSampleText.isEmpty) {
      throw ArgumentError.value(
        sampleText,
        'sampleText',
        'StepFun voice preview text is empty.',
      );
    }
    const family = AiApiFamily.audioVoicePreview;
    return _sendJson(
      model: model,
      family: family,
      body: <String, Object?>{
        'model': model.resolveOperationModelId(family),
        'file_id': trimmedFileId,
        'sample_text': trimmedSampleText,
        if (text?.trim().isNotEmpty == true) 'text': text!.trim(),
        if (responseFormat?.trim().isNotEmpty == true)
          'response_format': responseFormat!.trim(),
        if (speed != null && speed.isFinite) 'speed': speed,
        if (volume != null && volume.isFinite) 'volume': volume,
        if (voiceLabel != null) 'voice_label': voiceLabel,
        if (instruction?.trim().isNotEmpty == true)
          'instruction': instruction!.trim(),
        if (sampleRate != null && sampleRate > 0) 'sample_rate': sampleRate,
        if (pronunciationMap != null) 'pronunciation_map': pronunciationMap,
        if (markdownFilter != null) 'markdown_filter': markdownFilter,
      },
      timeout: timeout,
      contextHint: 'stepfun/audio/voices/preview',
    );
  }

  Future<AiStepFunAsrSubmitResult> submitAsrFileTask({
    required AiModelConfig model,
    required Map<String, Object?> audio,
    Map<String, Object?> request = const <String, Object?>{},
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (audio.isEmpty) {
      throw ArgumentError.value(
        audio,
        'audio',
        'StepFun ASR audio payload is empty.',
      );
    }
    const family = AiApiFamily.audioAsr;
    final response = await _sendJson(
      model: model,
      family: family,
      body: <String, Object?>{
        'audio': audio,
        'request': <String, Object?>{
          'model_name': model.resolveOperationModelId(family),
          ...request,
        },
      },
      timeout: timeout,
      contextHint: 'stepfun/audio/asr/submit',
    );
    return AiStepFunAsrSubmitResult(
      taskId: '${response.payload['task_id'] ?? ''}'.trim(),
      rawResponse: response.rawResponse,
      payload: response.payload,
    );
  }

  Future<AiStepFunPayloadResult> queryAsrFileTask({
    required AiModelConfig model,
    required String taskId,
    Duration timeout = const Duration(seconds: 60),
  }) {
    final trimmedTaskId = taskId.trim();
    if (trimmedTaskId.isEmpty) {
      throw ArgumentError.value(
        taskId,
        'taskId',
        'StepFun ASR task id is empty.',
      );
    }
    return _sendJson(
      model: model,
      family: AiApiFamily.audioAsr,
      fallbackPath: _asrQueryPath,
      body: <String, Object?>{'task_id': trimmedTaskId},
      timeout: timeout,
      contextHint: 'stepfun/audio/asr/query',
    );
  }

  Future<AiStepFunAsrSseResponse> transcribeSse({
    required AiModelConfig model,
    required String base64Audio,
    Map<String, Object?> transcription = const <String, Object?>{},
    Map<String, Object?> format = const <String, Object?>{},
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (base64Audio.trim().isEmpty) {
      throw ArgumentError.value(
        base64Audio,
        'base64Audio',
        'StepFun ASR audio data is empty.',
      );
    }
    const family = AiApiFamily.audioAsrSse;
    final body = <String, Object?>{
      'audio': <String, Object?>{
        'data': base64Audio,
        'input': <String, Object?>{
          'transcription': <String, Object?>{
            'model': model.resolveOperationModelId(family),
            ...transcription,
          },
          if (format.isNotEmpty) 'format': format,
        },
      },
    };
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
    );
    final response = await _transport.sendJson(
      uri: AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: family,
      )..['accept'] = 'text/event-stream',
      body: AiOperationHttp.mergeBodyExtras(model, family, body),
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'stepfun/audio/asr/sse',
    );
    final events = _parseSseEvents(response.body);
    final result = events.map((event) => event.delta).join().trim();
    return AiStepFunAsrSseResponse(
      events: events,
      result: result,
      rawResponse: response.body,
    );
  }

  Future<AiStepFunPayloadResult> _sendJson({
    required AiModelConfig model,
    required AiApiFamily family,
    required Map<String, Object?> body,
    required Duration timeout,
    required String contextHint,
    String? fallbackPath,
  }) async {
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
      fallbackPath: fallbackPath,
    );
    final response = await _transport.sendJson(
      uri: AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: family,
      ),
      body: AiOperationHttp.mergeBodyExtras(model, family, body),
      timeout: timeout,
    );
    return _parseResponse(response, contextHint: contextHint);
  }

  Future<AiStepFunPayloadResult> _sendJsonless({
    required AiModelConfig model,
    required AiApiFamily family,
    required String method,
    required Duration timeout,
    required String contextHint,
    String? fallbackPath,
    Map<String, String> query = const <String, String>{},
  }) async {
    final endpoint = _router.resolve(
      model,
      family,
      method: method,
      fallbackPath: fallbackPath,
    );
    final uri = _mergeQuery(
      AiOperationHttp.uriWithExtraQuery(endpoint.url, model, family),
      query,
    );
    final headers = AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpoint.headers,
      family: family,
      includeJsonContentType: false,
      acceptJson: true,
    );
    final response = method.toUpperCase() == 'GET'
        ? await _transport.get(uri: uri, headers: headers, timeout: timeout)
        : await _transport.sendJson(
            uri: uri,
            method: method,
            headers: headers,
            body: const <String, Object?>{},
            timeout: timeout,
          );
    return _parseResponse(response, contextHint: contextHint);
  }

  AiStepFunPayloadResult _parseResponse(
    http.Response response, {
    required String contextHint,
  }) {
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: contextHint,
    );
    final body = response.body;
    final decoded = body.trim().isEmpty
        ? const <String, Object?>{}
        : AiOperationHttp.decodeJsonResponse(body, contextHint: contextHint);
    return AiStepFunPayloadResult(
      rawResponse: body,
      payload: AiOperationHttp.jsonMapOrEmpty(decoded),
    );
  }

  Uri _mergeQuery(Uri uri, Map<String, String> query) {
    if (query.isEmpty) return uri;
    return uri.replace(
      queryParameters: <String, String>{...uri.queryParameters, ...query},
    );
  }

  Map<String, String> _paginationQuery({
    int? limit,
    String? order,
    String? before,
    String? after,
  }) {
    return <String, String>{
      if (limit != null && limit > 0) 'limit': '${limit.clamp(1, 100)}',
      if (order?.trim().isNotEmpty == true) 'order': order!.trim(),
      if (before?.trim().isNotEmpty == true) 'before': before!.trim(),
      if (after?.trim().isNotEmpty == true) 'after': after!.trim(),
    };
  }

  List<AiStepFunAsrSseEvent> _parseSseEvents(String body) {
    final events = <AiStepFunAsrSseEvent>[];
    final blocks = body
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n\n');
    for (final block in blocks) {
      var eventType = '';
      for (final line in block.split('\n')) {
        if (line.startsWith('event:')) {
          eventType = line.substring(6).trim();
        }
      }
      final dataLines = extractSseDataLines(block)
          .where((line) => line.isNotEmpty && line != '[DONE]')
          .toList(growable: false);
      if (dataLines.isEmpty) continue;
      final decoded = jsonDecode(dataLines.join('\n'));
      final payload = AiOperationHttp.jsonMapOrEmpty(decoded);
      if (payload.isEmpty) continue;
      events.add(
        AiStepFunAsrSseEvent(
          type: '${payload['type'] ?? eventType}'.trim(),
          payload: payload,
        ),
      );
    }
    return events;
  }

  List<Map<String, Object?>> _mapList(Object? raw) {
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map(AiOperationHttp.stringKeyedMap)
        .toList(growable: false);
  }

  int? _readNestedInt(Map<String, Object?> payload, List<String> path) {
    Object? current = payload;
    for (final key in path) {
      if (current is! Map) return null;
      current = current[key];
    }
    return _readInt(current);
  }

  int? _readInt(Object? value) {
    return optionalIntFromValue(value);
  }

  void _checkRequiredId(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'StepFun $name is empty.');
    }
  }

  AiTokenUsage? parseUsage(Map<String, Object?> payload) {
    final usage = payload['usage'];
    if (usage is Map<String, Object?>) {
      return AiTokenUsageParser.parseOpenAi(usage);
    }
    if (usage is Map) {
      return AiTokenUsageParser.parseOpenAi(stringKeyedMapFromValue(usage));
    }
    return null;
  }

  void dispose() {
    _transport.dispose();
  }
}
