import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/util/argument_guards.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/stable_hash.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_attachment.dart';
import '../../model/ai_creation_mode.dart';
import '../../model/ai_input_cache_runtime_config.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../chat/ai_chat_service.dart';
import '../chat/ai_protocol_adapter.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import '../session_io/ai_token_usage_parser.dart';
import 'ai_operation_http.dart';

typedef AiResponsesRequestStarted =
    void Function(AiResponsesRequestBlueprint request);

const String aiResponsesEmptyOutputMessage = 'Responses API 未返回助手正文或工具调用。';

class AiResponsesRequestBlueprint {
  const AiResponsesRequestBlueprint({
    required this.url,
    required this.method,
    required this.headers,
    required this.body,
  });

  final String url;
  final String method;
  final Map<String, String> headers;
  final Map<String, Object?> body;
}

class AiResponsesResult {
  const AiResponsesResult({
    required this.text,
    required this.rawResponse,
    this.reasoning,
    this.usage,
    this.toolCalls = const <AiToolCall>[],
    this.finishReason,
    this.requestUrl,
    this.requestMethod,
    this.requestHeaders,
    this.requestBody,
    this.startedAt,
    this.endedAt,
    this.durationMs,
    this.requestFallbacks = const <String>[],
  });

  final String text;
  final String rawResponse;
  final String? reasoning;
  final AiTokenUsage? usage;
  final List<AiToolCall> toolCalls;
  final String? finishReason;
  final String? requestUrl;
  final String? requestMethod;
  final Map<String, String>? requestHeaders;
  final Map<String, Object?>? requestBody;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationMs;
  final List<String> requestFallbacks;
}

class AiResponsesHttpException implements Exception {
  const AiResponsesHttpException({
    required this.statusCode,
    required this.body,
    required this.request,
    required this.startedAt,
    required this.endedAt,
    required this.requestFallbacks,
  });

  static const Set<int> _missingEndpointStatuses = <int>{404, 405, 410, 501};
  static const Set<int> _schemaCompatibilityStatuses = <int>{400, 415, 422};
  static const List<String> _incompatibilityTerms = <String>[
    'unknown',
    'unrecognized',
    'unsupported',
    'not supported',
    'not implemented',
    'unexpected',
    'additional propert',
    'no route',
    'cannot deserialize',
    '不支持',
    '未知',
    '无法识别',
    '未实现',
    '找不到路由',
  ];
  static const List<String> _responsesTerms = <String>[
    'response',
    'endpoint',
    'route',
    'path',
    'input',
    'content',
    'tool',
    'function_call',
    'image_generation',
    'model',
    'parameter',
    'field',
    'schema',
    '接口',
    '端点',
    '路由',
    '路径',
    '输入',
    '内容',
    '工具',
    '参数',
    '字段',
  ];

  final int statusCode;
  final String body;
  final AiResponsesRequestBlueprint request;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<String> requestFallbacks;

  bool get isMissingEndpoint => _missingEndpointStatuses.contains(statusCode);

  bool get isEndpointIncompatible {
    if (!isMissingEndpoint) return false;
    if (statusCode != HttpStatus.notFound) return true;
    final normalized = body.toLowerCase();
    if (AiTransportDiagnosticMessages.relayModelAvailabilityReason(
          normalized,
        ) !=
        null) {
      return false;
    }
    final resourceSpecificNotFound =
        const <String>['model', 'deployment'].any(normalized.contains) &&
        const <String>[
          'not found',
          'does not exist',
          'unknown',
          '找不到',
          '不存在',
          '未知',
        ].any(normalized.contains);
    return !resourceSpecificNotFound;
  }

  bool get isCompatibilityFailure {
    if (isMissingEndpoint) return isEndpointIncompatible;
    if (!_schemaCompatibilityStatuses.contains(statusCode)) return false;
    final normalized = body.toLowerCase();
    if (normalized.contains('responses_translation_error')) return true;
    return _incompatibilityTerms.any(normalized.contains) &&
        _responsesTerms.any(normalized.contains);
  }

  String get message => AiTransportDiagnosticMessages.httpStatus(
    statusCode,
    serverMessage: AiOperationHttp.extractErrorMessage(body),
    contextHint: 'responses',
  );

  @override
  String toString() => message;
}

class AiResponsesPayloadException implements Exception {
  const AiResponsesPayloadException(
    this.message, {
    this.request,
    this.body,
    this.startedAt,
    this.endedAt,
    this.requestFallbacks = const <String>[],
  });

  final String message;
  final AiResponsesRequestBlueprint? request;
  final String? body;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<String> requestFallbacks;

  bool get isEmptyOutput => message == aiResponsesEmptyOutputMessage;

  @override
  String toString() => message;
}

class AiResponsesStreamToolCall {
  AiResponsesStreamToolCall({this.id = '', this.name = ''});

  String id;
  String name;
  final StringBuffer arguments = StringBuffer();

  AiToolCall? toToolCall(int index) {
    final resolvedName = nullIfBlank(name);
    if (resolvedName == null) return null;
    return AiToolCall(
      id: nullIfBlank(id) ?? 'tool-call-$index',
      name: resolvedName,
      arguments: arguments.toString(),
    );
  }
}

class AiResponsesParsedPayload {
  const AiResponsesParsedPayload({
    required this.text,
    this.reasoning,
    this.usage,
    this.toolCalls = const <AiToolCall>[],
    this.finishReason,
  });

  final String text;
  final String? reasoning;
  final AiTokenUsage? usage;
  final List<AiToolCall> toolCalls;
  final String? finishReason;
}

class AiResponsesService {
  AiResponsesService({
    AiEndpointRouter? router,
    AiTransportClient? transport,
    http.Client? client,
  }) : _router = router ?? const AiEndpointRouter(),
       _transport = transport ?? AiTransportClient(client: client),
       _ownsTransport = transport == null {
    requireAtMostOneProvided(
      firstValue: transport,
      firstName: 'transport',
      secondValue: client,
      secondName: 'client',
    );
  }

  final AiEndpointRouter _router;
  final AiTransportClient _transport;
  final bool _ownsTransport;

  AiResponsesRequestBlueprint buildRequest({
    required AiModelConfig model,
    required Object input,
    bool stream = false,
    String? instructions,
    String? previousResponseId,
    bool? store,
    Map<String, Object?>? metadata,
    double? temperature,
    int? maxOutputTokens,
    double? topP,
    Object? reasoning,
    Object? text,
    Object? tools,
    Object? toolChoice,
    String? user,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) {
    const family = AiApiFamily.responses;
    final instructionsValue = nullIfBlank(instructions);
    final previousResponseIdValue = nullIfBlank(previousResponseId);
    final userValue = nullIfBlank(user);
    final mimo = model.protocolType == AiProtocolType.mimo;
    if (mimo &&
        !lowercaseStringFromValue(model.modelId).contains('mimo-v2.5')) {
      throw ArgumentError.value(
        model.modelId,
        'modelId',
        'MiMo official API only supports the V2.5 model family.',
      );
    }
    final reasoningValue =
        reasoning ?? AiThinkingRequestPolicy.responsesReasoningFor(model);
    final mimoThinkingEnabled =
        mimo &&
        reasoningValue is Map &&
        lowercaseStringFromValue(reasoningValue['effort']) != 'none';
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
    );
    final baseBody = <String, Object?>{
      'model': model.resolveOperationModelId(family),
      if (instructionsValue != null) 'instructions': instructionsValue,
      if (!mimo && previousResponseIdValue != null)
        'previous_response_id': previousResponseIdValue,
      if (!mimo && store != null) 'store': store,
      if (!mimo && metadata != null && metadata.isNotEmpty)
        'metadata': metadata,
      if (!mimoThinkingEnabled && temperature != null && temperature.isFinite)
        'temperature': temperature,
      if (!mimoThinkingEnabled &&
          temperature == null &&
          model.temperature != null)
        'temperature': model.temperature,
      if (maxOutputTokens != null && maxOutputTokens > 0)
        'max_output_tokens': maxOutputTokens,
      if (maxOutputTokens == null && model.maxTokens != null)
        'max_output_tokens': model.maxTokens,
      if (!mimoThinkingEnabled && topP != null && topP.isFinite) 'top_p': topP,
      if (reasoningValue != null) 'reasoning': reasoningValue,
      if (text != null) 'text': text,
      if (tools != null) 'tools': tools,
      if (toolChoice != null) 'tool_choice': toolChoice,
      if (!mimo && userValue != null) 'user': userValue,
      if (stream) 'stream': true,
      // 把持续增长的会话输入放在末尾，使服务端前缀缓存在多轮间保持稳定。
      'input': input,
    };
    final cacheAffinity = AiPromptCacheAffinity.resolve(
      model: model,
      inputCacheConfig: inputCacheConfig,
    );
    final headers = AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpoint.headers,
      family: family,
    );
    cacheAffinity.applyToHeaders(headers);
    final body = AiPromptCacheAffinity.withConversationInputLast(
      AiPromptCacheRetentionPolicy.applyToBody(
        model: model,
        inputCacheConfig: inputCacheConfig,
        body: cacheAffinity.applyToBody(
          AiOperationHttp.mergeBodyExtras(model, family, baseBody),
        ),
      ),
    );
    if (mimo) _normalizeMimoRequestBody(body);
    AiThinkingRequestPolicy.normalizeModelRequestBody(body, model);
    return AiResponsesRequestBlueprint(
      url: AiOperationHttp.uriWithExtraQuery(
        endpoint.url,
        model,
        family,
      ).toString(),
      method: endpoint.method,
      headers: headers,
      body: body,
    );
  }

  static void _normalizeMimoRequestBody(Map<String, Object?> body) {
    for (final field in const <String>{
      'background',
      'context_management',
      'metadata',
      'previous_response_id',
      'store',
      'user',
    }) {
      body.remove(field);
    }
    final reasoning = body['reasoning'];
    final thinkingEnabled =
        reasoning is Map &&
        lowercaseStringFromValue(reasoning['effort']) != 'none';
    if (thinkingEnabled) {
      body.remove('temperature');
      body.remove('top_p');
    }
    final text = body['text'];
    if (text != null) {
      if (text is! Map) {
        throw ArgumentError.value(
          text,
          'text',
          'MiMo Responses text configuration must be an object.',
        );
      }
      final textConfig = Map<String, Object?>.from(
        stringKeyedMapFromValue(text),
      );
      final format = textConfig['format'];
      if (format != null) {
        if (format is! Map) {
          throw ArgumentError.value(
            format,
            'text.format',
            'MiMo Responses text.format must be an object.',
          );
        }
        final type = lowercaseStringFromValue(format['type']);
        if (type != 'text' && type != 'json_object' && type != 'json_schema') {
          throw ArgumentError.value(
            format['type'],
            'text.format.type',
            'MiMo Responses only supports text and json_object formats.',
          );
        }
        textConfig['format'] = <String, Object?>{
          'type': type == 'json_schema' ? 'json_object' : type,
        };
      }
      body['text'] = textConfig;
    }
    if (body['tools'] is List && (body['tools']! as List).isNotEmpty) {
      body['tool_choice'] = 'auto';
    } else {
      body.remove('tool_choice');
    }
  }

  Future<AiResponsesRequestBlueprint> buildChatRequest({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiCreationOptions? imageGenerationOptions,
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    if (model.protocolType == AiProtocolType.mimo) {
      await validateMimoContentParts(
        model,
        messages,
        surface: AiMimoMediaSurface.responses,
      );
    }
    final stableTools = stableToolDefinitionsForAiRequest(tools);
    final responseTools = <Map<String, Object?>>[
      ...stableTools.map(
        (tool) => <String, Object?>{
          'type': 'function',
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.parameters,
          if (tool.strict != null) 'strict': tool.strict,
        },
      ),
      if (imageGenerationOptions != null)
        _imageGenerationTool(imageGenerationOptions),
    ];
    return buildRequest(
      model: model,
      input: await _mapConversationInput(messages, model: model),
      stream: stream,
      tools: responseTools.isEmpty ? null : responseTools,
      toolChoice: imageGenerationOptions != null
          ? const <String, Object?>{'type': 'image_generation'}
          : responseTools.isEmpty
          ? null
          : 'auto',
      inputCacheConfig: inputCacheConfig,
    );
  }

  Future<AiResponsesResult> createChatResponse({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiCreationOptions? imageGenerationOptions,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    AiResponsesRequestStarted? onRequestStarted,
    Future<void>? cancelSignal,
  }) async {
    return createResponseFromRequest(
      request: await buildChatRequest(
        model: model,
        messages: messages,
        tools: tools,
        imageGenerationOptions: imageGenerationOptions,
        inputCacheConfig: inputCacheConfig,
      ),
      timeout: timeout,
      onRequestStarted: onRequestStarted,
      cancelSignal: cancelSignal,
    );
  }

  Map<String, Object?> _imageGenerationTool(AiCreationOptions options) {
    final size = _responsesImageSize(options);
    final quality = switch (lowercaseStringFromValue(options.quality)) {
      'standard' => 'medium',
      'hd' => 'high',
      final value when value.isNotEmpty => value,
      _ => null,
    };
    return <String, Object?>{
      'type': 'image_generation',
      if (size != null) 'size': size,
      if (quality != null) 'quality': quality,
      if (nullIfBlank(options.background) != null)
        'background': options.background,
      if (nullIfBlank(options.outputFormat) != null)
        'output_format': options.outputFormat,
    };
  }

  String? _responsesImageSize(AiCreationOptions options) {
    final size = nullIfBlank(options.size);
    if (size == '1024x1024' ||
        size == '1536x1024' ||
        size == '1024x1536' ||
        size == 'auto') {
      return size;
    }
    final ratio = nullIfBlank(options.aspectRatio);
    if (ratio == null && size == null) return null;
    final parts = (ratio ?? size!.replaceFirst('x', ':')).split(':');
    if (parts.length != 2) return null;
    final width = double.tryParse(parts.first);
    final height = double.tryParse(parts.last);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    if ((width - height).abs() / width < 0.08) return '1024x1024';
    return width > height ? '1536x1024' : '1024x1536';
  }

  Future<AiResponsesResult> createResponseFromRequest({
    required AiResponsesRequestBlueprint request,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
    AiResponsesRequestStarted? onRequestStarted,
    Future<void>? cancelSignal,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final requestFallbacks = <String>[];
    if (AiPromptCacheRetentionPolicy.wasRecentlyRejected(
      requestUrl: request.url,
      requestBody: request.body,
    )) {
      request = _withoutCacheRetentionMarker(request);
    }

    Future<http.Response> send() async {
      onRequestStarted?.call(request);
      return _transport.sendJson(
        uri: Uri.parse(request.url),
        method: request.method,
        headers: request.headers,
        body: request.body,
        timeout: timeout,
        cancelSignal: cancelSignal,
      );
    }

    var response = await send();
    if (isHttpFailureStatus(response.statusCode) &&
        AiPromptCacheRetentionPolicy.shouldRetryWithoutMarker(
          statusCode: response.statusCode,
          errorBody: response.body,
          requestBody: request.body,
        )) {
      AiPromptCacheRetentionPolicy.rememberRejection(
        requestUrl: request.url,
        requestBody: request.body,
      );
      _addRequestFallback(
        requestFallbacks,
        aiChatRequestFallbackCacheRetentionRejected,
      );
      request = _withoutCacheRetentionMarker(request);
      response = await send();
    }
    if (isHttpFailureStatus(response.statusCode) &&
        AiPromptCacheAffinity.shouldRetryWithoutMarkers(
          statusCode: response.statusCode,
          errorBody: response.body,
          requestBody: request.body,
          requestHeaders: request.headers,
        )) {
      _addRequestFallback(
        requestFallbacks,
        aiChatRequestFallbackCacheAffinityRejected,
      );
      request = _withoutCacheAffinityMarkers(request);
      response = await send();
    }
    if (isHttpFailureStatus(response.statusCode) &&
        AiThinkingRequestPolicy.shouldRetryWithoutMarkers(
          statusCode: response.statusCode,
          errorBody: response.body,
          requestBody: request.body,
        )) {
      _addRequestFallback(
        requestFallbacks,
        aiChatRequestFallbackThinkingMarkersRejected,
      );
      request = _withoutThinkingMarkers(request);
      response = await send();
    }
    final endedAt = DateTime.now().toUtc();
    if (isHttpFailureStatus(response.statusCode)) {
      throw AiResponsesHttpException(
        statusCode: response.statusCode,
        body: response.body,
        request: request,
        startedAt: startedAt,
        endedAt: endedAt,
        requestFallbacks: List<String>.unmodifiable(requestFallbacks),
      );
    }
    final Object? decoded;
    try {
      decoded = AiOperationHttp.decodeJsonResponse(
        response.body,
        contextHint: 'responses',
      );
    } on FormatException catch (error) {
      throw AiResponsesPayloadException(
        error.message,
        request: request,
        body: response.body,
        startedAt: startedAt,
        endedAt: endedAt,
        requestFallbacks: List<String>.unmodifiable(requestFallbacks),
      );
    }
    if (decoded is Map) {
      final payload = stringKeyedMapFromValue(decoded);
      final status = lowercaseStringFromValue(payload['status']);
      if (status == 'failed' || status == 'cancelled') {
        throw AiResponsesPayloadException(
          AiOperationHttp.extractErrorMessage(
            jsonEncode(payload['error'] ?? payload),
          ),
          request: request,
          body: response.body,
          startedAt: startedAt,
          endedAt: endedAt,
          requestFallbacks: List<String>.unmodifiable(requestFallbacks),
        );
      }
    }
    final parsed = await parseResponsePayload(decoded);
    if (parsed.text.isEmpty && parsed.toolCalls.isEmpty) {
      throw AiResponsesPayloadException(
        aiResponsesEmptyOutputMessage,
        request: request,
        body: response.body,
        startedAt: startedAt,
        endedAt: endedAt,
        requestFallbacks: List<String>.unmodifiable(requestFallbacks),
      );
    }
    return AiResponsesResult(
      text: parsed.text,
      rawResponse: response.body,
      reasoning: parsed.reasoning,
      usage: parsed.usage,
      toolCalls: parsed.toolCalls,
      finishReason: parsed.finishReason,
      requestUrl: request.url,
      requestMethod: request.method,
      requestHeaders: Map<String, String>.unmodifiable(request.headers),
      requestBody: request.body,
      startedAt: startedAt,
      endedAt: endedAt,
      durationMs: endedAt.difference(startedAt).inMilliseconds,
      requestFallbacks: List<String>.unmodifiable(requestFallbacks),
    );
  }

  Future<List<Map<String, Object?>>> _mapConversationInput(
    List<AiChatTurn> messages, {
    required AiModelConfig model,
  }) async {
    final input = <Map<String, Object?>>[];
    final knownToolCallIds = <String>{};
    final outstandingToolCallIds = <String>{};
    final pendingToolReminders = <String>[];
    for (final turn in messages) {
      if (turn.role == AiChatRole.tool) {
        final toolCallId = nullIfBlank(turn.toolCallId);
        if (toolCallId != null && knownToolCallIds.contains(toolCallId)) {
          final output = <String>[
            if (nullIfBlank(turn.content) != null) turn.content,
            ...pendingToolReminders,
          ].join('\n\n');
          input.add(<String, Object?>{
            'type': 'function_call_output',
            'call_id': toolCallId,
            'output': output,
          });
          outstandingToolCallIds.remove(toolCallId);
          pendingToolReminders.clear();
        } else if (nullIfBlank(turn.content) != null) {
          input.add(<String, Object?>{
            'role': 'user',
            'content': '[tool_result]\n${turn.content}',
          });
        }
        continue;
      }

      final systemContent = nullIfBlank(turn.content);
      if (turn.role == AiChatRole.system &&
          outstandingToolCallIds.isNotEmpty &&
          systemContent?.startsWith('# System Reminder') == true) {
        pendingToolReminders.add(systemContent!);
        continue;
      }
      if (pendingToolReminders.isNotEmpty) {
        input.add(<String, Object?>{
          'role': 'system',
          'content': pendingToolReminders.join('\n\n'),
        });
        pendingToolReminders.clear();
      }

      final content = await _mapMessageContent(turn, model: model);
      final reasoning =
          turn.role == AiChatRole.assistant && model.requiresReasoningEcho
          ? nullIfBlank(turn.reasoningContent)
          : null;
      if (reasoning != null) {
        input.add(<String, Object?>{
          'id': 'rs_${stableSha256Hex(reasoning, length: 24)}',
          'type': 'reasoning',
          'status': 'completed',
          'content': <Map<String, Object?>>[
            <String, Object?>{'type': 'reasoning_text', 'text': reasoning},
          ],
        });
      }
      if (content != null) {
        input.add(<String, Object?>{'role': turn.roleName, 'content': content});
      }
      if (turn.role == AiChatRole.assistant && turn.toolCalls.isNotEmpty) {
        for (final toolCall in turn.toolCalls) {
          final callId = nullIfBlank(toolCall.id);
          final name = nullIfBlank(toolCall.name);
          if (callId == null || name == null) continue;
          knownToolCallIds.add(callId);
          outstandingToolCallIds.add(callId);
          input.add(<String, Object?>{
            'type': 'function_call',
            'call_id': callId,
            'name': name,
            'arguments': toolCall.arguments,
          });
        }
      }
    }
    if (pendingToolReminders.isNotEmpty) {
      input.add(<String, Object?>{
        'role': 'system',
        'content': pendingToolReminders.join('\n\n'),
      });
    }
    if (outstandingToolCallIds.isNotEmpty) {
      input.removeWhere(
        (item) =>
            item['type'] == 'function_call' &&
            outstandingToolCallIds.contains(item['call_id']),
      );
      input.add(<String, Object?>{
        'role': 'assistant',
        'content':
            '[tool_exchange_repaired]\nIncomplete tool calls omitted: '
            '${outstandingToolCallIds.join(', ')}',
      });
    }
    return input;
  }

  Future<Object?> _mapMessageContent(
    AiChatTurn turn, {
    required AiModelConfig model,
  }) async {
    final parts = turn.effectiveParts;
    if (parts.isEmpty) return nullIfBlank(turn.content);
    if (parts.every((part) => part.kind == AiChatContentPartKind.text)) {
      return trimmedNonEmptyStrings(
        parts.map((part) => part.text),
      ).join('\n\n');
    }
    const encoder = OpenAiProtocolAdapter(AiProtocolType.openai);
    final inlineMaxBytes = model.protocolType == AiProtocolType.mimo
        ? aiMimoUnderstandingMaxRawBytes
        : aiMessageAttachmentMaxFileBytes;
    final isMiniMax = model.protocolType == AiProtocolType.minimax;
    final content = <Map<String, Object?>>[];
    for (final part in parts) {
      switch (part.kind) {
        case AiChatContentPartKind.text:
          final text = nullIfBlank(part.text);
          if (text != null) {
            content.add(<String, Object?>{
              'type': turn.role == AiChatRole.assistant
                  ? 'output_text'
                  : 'input_text',
              'text': text,
            });
          }
        case AiChatContentPartKind.imageFile:
        case AiChatContentPartKind.videoFile:
        case AiChatContentPartKind.audioFile:
          final filePath = nullIfBlank(part.filePath);
          final mimeType = nullIfBlank(part.mimeType);
          if (filePath == null || mimeType == null) continue;
          final dataUrl = await encoder.encodeFileAsDataUrl(
            filePath: filePath,
            mimeType: mimeType,
            maxBytes: inlineMaxBytes,
          );
          if (part.kind == AiChatContentPartKind.audioFile) {
            content.add(<String, Object?>{
              'type': 'input_audio',
              'input_audio': <String, Object?>{'data': dataUrl},
            });
            continue;
          }
          final urlKey = part.kind == AiChatContentPartKind.videoFile
              ? 'video_url'
              : 'image_url';
          content.add(<String, Object?>{
            'type': part.kind == AiChatContentPartKind.videoFile
                ? 'input_video'
                : 'input_image',
            if (isMiniMax)
              urlKey: <String, Object?>{'url': dataUrl, 'detail': 'default'}
            else ...<String, Object?>{urlKey: dataUrl, 'detail': 'auto'},
          });
      }
    }
    return content.isEmpty ? null : content;
  }

  void _addRequestFallback(List<String> fallbacks, String reason) {
    if (reason.isEmpty || fallbacks.contains(reason)) return;
    fallbacks.add(reason);
  }

  AiResponsesRequestBlueprint _withoutCacheAffinityMarkers(
    AiResponsesRequestBlueprint request,
  ) {
    return AiResponsesRequestBlueprint(
      url: request.url,
      method: request.method,
      headers: AiPromptCacheAffinity.withoutHeaderMarkers(request.headers),
      body: AiPromptCacheAffinity.withoutBodyMarkers(request.body),
    );
  }

  AiResponsesRequestBlueprint _withoutCacheRetentionMarker(
    AiResponsesRequestBlueprint request,
  ) {
    return AiResponsesRequestBlueprint(
      url: request.url,
      method: request.method,
      headers: request.headers,
      body: AiPromptCacheRetentionPolicy.withoutMarker(request.body),
    );
  }

  AiResponsesRequestBlueprint _withoutThinkingMarkers(
    AiResponsesRequestBlueprint request,
  ) {
    return AiResponsesRequestBlueprint(
      url: request.url,
      method: request.method,
      headers: request.headers,
      body: AiThinkingRequestPolicy.withoutRequestMarkers(request.body),
    );
  }

  Future<AiResponsesParsedPayload> parseResponsePayload(Object? decoded) async {
    if (decoded is! Map) {
      return const AiResponsesParsedPayload(text: '');
    }
    final payload = stringKeyedMapFromValue(decoded);
    final textBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final toolCalls = <AiToolCall>[];
    final directText = _responseTextValue(
      payload['output_text'] ?? payload['text'],
    );

    final output = payload['output'];
    if (output is List) {
      for (final rawItem in output) {
        if (rawItem is! Map) continue;
        final item = stringKeyedMapFromValue(rawItem);
        final itemType = '${item['type'] ?? ''}'.trim();
        if (itemType == 'reasoning') {
          _appendResponseText(reasoningBuffer, item['summary']);
          _appendResponseText(reasoningBuffer, item['content']);
          continue;
        }
        if (itemType == 'function_call') {
          final toolCall = _toolCallFromResponseItem(item);
          if (toolCall != null) toolCalls.add(toolCall);
          continue;
        }
        final mediaMarkdown = await _mediaMarkdownFromResponsePart(
          item,
          itemType: itemType,
        );
        if (mediaMarkdown.isNotEmpty) {
          _appendResponseText(textBuffer, mediaMarkdown);
        }
        final content = item['content'];
        if (content is! List) {
          if (itemType == 'message') _appendResponseText(textBuffer, content);
          continue;
        }
        for (final rawPart in content) {
          if (rawPart is! Map) continue;
          final part = stringKeyedMapFromValue(rawPart);
          final type = '${part['type'] ?? ''}'.trim();
          if (type == 'output_text' || type == 'text' || type == 'refusal') {
            _appendResponseText(textBuffer, part['text'] ?? part['refusal']);
          } else if (type == 'reasoning' || type == 'summary_text') {
            _appendResponseText(
              reasoningBuffer,
              part['summary'] ?? part['text'],
            );
          }
          final partMedia = await _mediaMarkdownFromResponsePart(
            part,
            itemType: type,
          );
          if (partMedia.isNotEmpty) {
            _appendResponseText(textBuffer, partMedia);
          }
        }
      }
    }

    if (textBuffer.isEmpty && directText.isNotEmpty) {
      textBuffer.write(directText);
    }
    if (textBuffer.isEmpty) {
      _appendResponseText(textBuffer, _parseChatChoiceText(payload));
    }
    if (toolCalls.isEmpty) {
      toolCalls.addAll(_parseChatChoiceToolCalls(payload));
    }
    final usage = _parseUsage(payload['usage']);
    return AiResponsesParsedPayload(
      text: textBuffer.toString().trim(),
      reasoning: nullIfBlank(reasoningBuffer.toString()),
      usage: usage,
      toolCalls: List<AiToolCall>.unmodifiable(toolCalls),
      finishReason: _finishReason(payload, hasToolCalls: toolCalls.isNotEmpty),
    );
  }

  AiTokenUsage? _parseUsage(Object? rawUsage) {
    if (rawUsage is! Map) return null;
    return AiTokenUsageParser.parseOpenAi(stringKeyedMapFromValue(rawUsage));
  }

  String? _finishReason(
    Map<String, Object?> payload, {
    required bool hasToolCalls,
  }) {
    if (hasToolCalls) return 'tool_calls';
    final status = optionalStringFromValue(payload['status']);
    if (status == 'completed') return 'stop';
    if (status == 'failed' || status == 'cancelled') return status;
    if (status == 'incomplete') {
      final details = payload['incomplete_details'];
      if (details is Map) {
        return optionalStringFromValue(details['reason']) ?? 'incomplete';
      }
      return 'incomplete';
    }
    final choices = payload['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      return optionalStringFromValue((choices.first as Map)['finish_reason']);
    }
    return null;
  }

  AiToolCall? _toolCallFromResponseItem(Map<String, Object?> item) {
    final id =
        optionalStringFromValue(item['call_id']) ??
        optionalStringFromValue(item['id']);
    final name = optionalStringFromValue(item['name']);
    if (id == null || name == null) return null;
    return AiToolCall(
      id: id,
      name: name,
      arguments: _argumentsText(item['arguments']),
    );
  }

  String _argumentsText(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map || value is List) return jsonEncode(value);
    return '$value';
  }

  Future<String> _mediaMarkdownFromResponsePart(
    Map<String, Object?> part, {
    required String itemType,
  }) async {
    String? mimeType;
    Object? rawData;
    String? label;
    if (itemType == 'image_generation_call' ||
        itemType == 'output_image' ||
        itemType == 'image') {
      mimeType = optionalStringFromValue(part['mime_type']);
      rawData = part['result'] ?? part['data'] ?? part['b64_json'];
      label = 'AI Generated Image';
    } else if (itemType == 'output_audio' || itemType == 'audio') {
      mimeType =
          optionalStringFromValue(part['mime_type']) ?? kAudioMpegMimeType;
      rawData = part['data'] ?? part['audio'] ?? part['result'];
      label = optionalStringFromValue(part['transcript']) ?? 'AI Audio';
    } else if (itemType == 'output_video' || itemType == 'video') {
      mimeType =
          optionalStringFromValue(part['mime_type']) ?? kVideoMp4MimeType;
      rawData = part['data'] ?? part['video'] ?? part['result'];
      label = 'AI Video';
    } else {
      return '';
    }
    final url =
        optionalStringFromValue(part['url']) ??
        optionalStringFromValue(part['image_url']) ??
        optionalStringFromValue(part['audio_url']) ??
        optionalStringFromValue(part['video_url']);
    if (url != null) {
      final safeLabel = sanitizeMarkdownAltText(label);
      return isImageMimeType(mimeType ?? _defaultMediaMimeType(itemType))
          ? '![$safeLabel]($url)'
          : '[$safeLabel]($url)';
    }
    final base64Data = optionalStringFromValue(rawData);
    if (base64Data == null) return '';
    mimeType ??= itemType.contains('image')
        ? _imageMimeTypeFromBase64(base64Data)
        : _defaultMediaMimeType(itemType);
    return saveInlineMediaToMarkdown(
      AiInlineMedia(mimeType: mimeType, base64Data: base64Data),
      label: label,
    );
  }

  String _defaultMediaMimeType(String itemType) {
    if (itemType.contains('audio')) return kAudioMpegMimeType;
    if (itemType.contains('video')) return kVideoMp4MimeType;
    return kImagePngMimeType;
  }

  String _imageMimeTypeFromBase64(String value) {
    if (value.startsWith('/9j/')) return kImageJpegMimeType;
    if (value.startsWith('UklGR')) return kImageWebpMimeType;
    if (value.startsWith('R0lGOD')) return kImageGifMimeType;
    return kImagePngMimeType;
  }

  String _parseChatChoiceText(Map<String, Object?> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return '';
    final choice = stringKeyedMapFromValue(choices.first);
    final message = choice['message'];
    if (message is Map) {
      final content = message['content'];
      if (content is String) return content.trim();
      if (content is List) {
        return trimmedNonEmptyStrings(
          content.whereType<Map>().map((item) => item['text']),
        ).join('\n').trim();
      }
    }
    return '${choice['text'] ?? ''}'.trim();
  }

  List<AiToolCall> _parseChatChoiceToolCalls(Map<String, Object?> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return const <AiToolCall>[];
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map || message['tool_calls'] is! List) {
      return const <AiToolCall>[];
    }
    return (message['tool_calls'] as List)
        .map((raw) {
          if (raw is! Map || raw['function'] is! Map) return null;
          final function = raw['function'] as Map;
          final id = optionalStringFromValue(raw['id']);
          final name = optionalStringFromValue(function['name']);
          if (id == null || name == null) return null;
          return AiToolCall(
            id: id,
            name: name,
            arguments: _argumentsText(function['arguments']),
          );
        })
        .whereType<AiToolCall>()
        .toList(growable: false);
  }

  void _appendResponseText(StringBuffer buffer, Object? value) {
    final text = _responseTextValue(value);
    if (text.isEmpty) return;
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.write(text);
  }

  String _responseTextValue(Object? value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is List) {
      return value
          .map(_responseTextValue)
          .where((item) => item.isNotEmpty)
          .join('\n')
          .trim();
    }
    if (value is Map) {
      final direct =
          value['text'] ??
          value['summary'] ??
          value['content'] ??
          value['value'];
      return _responseTextValue(direct);
    }
    return '';
  }

  void parseSseEvent(
    Map<String, Object?> decoded, {
    required StringBuffer textBuffer,
    required StringBuffer reasoningBuffer,
    required Map<int, AiResponsesStreamToolCall> toolCalls,
    required AiTokenUsage? Function() usage,
    required void Function(AiTokenUsage?) setUsage,
    required void Function(AiChatStreamEvent) emitEvent,
    required void Function(String) setFinishReason,
    required void Function(Map<String, Object?>) setCompletedResponse,
  }) {
    if (decoded['choices'] is List) {
      _parseChatCompatibleSseEvent(
        decoded,
        textBuffer: textBuffer,
        reasoningBuffer: reasoningBuffer,
        toolCalls: toolCalls,
        usage: usage,
        setUsage: setUsage,
        emitEvent: emitEvent,
        setFinishReason: setFinishReason,
      );
      return;
    }
    final type = '${decoded['type'] ?? ''}'.trim();
    if (type == 'response.output_text.delta' ||
        type == 'response.refusal.delta') {
      final delta = '${decoded['delta'] ?? ''}';
      if (delta.isNotEmpty) {
        textBuffer.write(delta);
        emitEvent(AiChatStreamEvent.textDelta(delta));
      }
      return;
    }
    if (type == 'response.reasoning.delta' ||
        type == 'response.reasoning_text.delta' ||
        type == 'response.reasoning_summary_text.delta') {
      final delta = '${decoded['delta'] ?? ''}';
      if (delta.isNotEmpty) {
        reasoningBuffer.write(delta);
        emitEvent(AiChatStreamEvent.reasoningDelta(delta));
      }
      return;
    }
    if (type == 'response.output_item.added' ||
        type == 'response.output_item.done') {
      final rawItem = decoded['item'];
      if (rawItem is Map) {
        _mergeStreamToolCall(
          stringKeyedMapFromValue(rawItem),
          index: _streamOutputIndex(decoded, toolCalls.length),
          toolCalls: toolCalls,
          emitEvent: emitEvent,
          replaceArguments: type.endsWith('.done'),
        );
      }
      return;
    }
    if (type == 'response.function_call_arguments.delta' ||
        type == 'response.function_call_arguments.done') {
      final index = _streamOutputIndex(decoded, toolCalls.length);
      final entry = toolCalls.putIfAbsent(
        index,
        () => AiResponsesStreamToolCall(
          id:
              optionalStringFromValue(decoded['call_id']) ??
              optionalStringFromValue(decoded['item_id']) ??
              '',
          name: optionalStringFromValue(decoded['name']) ?? '',
        ),
      );
      final fragment = type.endsWith('.delta')
          ? '${decoded['delta'] ?? ''}'
          : _argumentsText(decoded['arguments']);
      if (fragment.isNotEmpty) {
        if (type.endsWith('.done') && entry.arguments.isNotEmpty) {
          final accumulated = entry.arguments.toString();
          if (fragment != accumulated) {
            entry.arguments
              ..clear()
              ..write(fragment);
          }
        } else {
          entry.arguments.write(fragment);
        }
      }
      emitEvent(
        AiChatStreamEvent.toolCallDelta(
          AiToolCallDelta(
            index: index,
            id: nullIfBlank(entry.id),
            name: nullIfBlank(entry.name),
            argumentsFragment: type.endsWith('.delta') ? fragment : '',
          ),
        ),
      );
      return;
    }
    if (type == 'response.completed' || type == 'response.incomplete') {
      final response = decoded['response'];
      if (response is Map) {
        final responseMap = stringKeyedMapFromValue(response);
        setCompletedResponse(responseMap);
        final parsedUsage = _parseUsage(responseMap['usage']);
        if (parsedUsage != null && !parsedUsage.isEmpty) {
          final merged = AiTokenUsageParser.carryForward(usage(), parsedUsage);
          setUsage(merged);
          emitEvent(AiChatStreamEvent.usage(merged));
        }
        setFinishReason(
          _finishReason(responseMap, hasToolCalls: toolCalls.isNotEmpty) ??
              (type == 'response.completed' ? 'stop' : 'incomplete'),
        );
      }
      return;
    }
    if (type == 'response.failed' || type == 'error') {
      setFinishReason('error');
    }
  }

  void _parseChatCompatibleSseEvent(
    Map<String, Object?> decoded, {
    required StringBuffer textBuffer,
    required StringBuffer reasoningBuffer,
    required Map<int, AiResponsesStreamToolCall> toolCalls,
    required AiTokenUsage? Function() usage,
    required void Function(AiTokenUsage?) setUsage,
    required void Function(AiChatStreamEvent) emitEvent,
    required void Function(String) setFinishReason,
  }) {
    final parsedUsage = _parseUsage(decoded['usage']);
    if (parsedUsage != null && !parsedUsage.isEmpty) {
      final merged = AiTokenUsageParser.carryForward(usage(), parsedUsage);
      setUsage(merged);
      emitEvent(AiChatStreamEvent.usage(merged));
    }
    final choices = decoded['choices'];
    if (choices is! List) return;
    for (final rawChoice in choices) {
      if (rawChoice is! Map) continue;
      final choice = stringKeyedMapFromValue(rawChoice);
      final reason = optionalStringFromValue(choice['finish_reason']);
      if (reason != null) setFinishReason(reason);
      final rawDelta = choice['delta'];
      if (rawDelta is! Map) continue;
      final delta = stringKeyedMapFromValue(rawDelta);
      final rawText = delta['content'];
      final text = rawText is String ? rawText : _responseTextValue(rawText);
      if (text.isNotEmpty) {
        textBuffer.write(text);
        emitEvent(AiChatStreamEvent.textDelta(text));
      }
      final rawReasoning = delta['reasoning_content'] ?? delta['reasoning'];
      final reasoning = rawReasoning is String
          ? rawReasoning
          : _responseTextValue(rawReasoning);
      if (reasoning.isNotEmpty) {
        reasoningBuffer.write(reasoning);
        emitEvent(AiChatStreamEvent.reasoningDelta(reasoning));
      }
      final rawToolCalls = delta['tool_calls'];
      if (rawToolCalls is! List) continue;
      for (final rawToolCall in rawToolCalls) {
        if (rawToolCall is! Map) continue;
        final toolCall = stringKeyedMapFromValue(rawToolCall);
        final index =
            optionalIntegralIntFromValue(toolCall['index']) ?? toolCalls.length;
        final entry = toolCalls.putIfAbsent(
          index,
          AiResponsesStreamToolCall.new,
        );
        entry.id = optionalStringFromValue(toolCall['id']) ?? entry.id;
        final rawFunction = toolCall['function'];
        if (rawFunction is! Map) continue;
        final function = stringKeyedMapFromValue(rawFunction);
        entry.name = optionalStringFromValue(function['name']) ?? entry.name;
        final arguments = _argumentsText(function['arguments']);
        if (arguments.isNotEmpty) entry.arguments.write(arguments);
        emitEvent(
          AiChatStreamEvent.toolCallDelta(
            AiToolCallDelta(
              index: index,
              id: nullIfBlank(entry.id),
              name: nullIfBlank(entry.name),
              argumentsFragment: arguments,
            ),
          ),
        );
      }
    }
  }

  int _streamOutputIndex(Map<String, Object?> event, int fallback) {
    return optionalIntegralIntFromValue(event['output_index']) ??
        optionalIntegralIntFromValue(event['index']) ??
        fallback;
  }

  void _mergeStreamToolCall(
    Map<String, Object?> item, {
    required int index,
    required Map<int, AiResponsesStreamToolCall> toolCalls,
    required void Function(AiChatStreamEvent) emitEvent,
    required bool replaceArguments,
  }) {
    if ('${item['type'] ?? ''}' != 'function_call') return;
    final entry = toolCalls.putIfAbsent(index, AiResponsesStreamToolCall.new);
    entry.id =
        optionalStringFromValue(item['call_id']) ??
        optionalStringFromValue(item['id']) ??
        entry.id;
    entry.name = optionalStringFromValue(item['name']) ?? entry.name;
    final arguments = _argumentsText(item['arguments']);
    var fragment = '';
    if (arguments.isNotEmpty) {
      if (replaceArguments) {
        if (entry.arguments.toString() != arguments) {
          entry.arguments
            ..clear()
            ..write(arguments);
        }
      } else if (entry.arguments.isEmpty) {
        entry.arguments.write(arguments);
        fragment = arguments;
      }
    }
    emitEvent(
      AiChatStreamEvent.toolCallDelta(
        AiToolCallDelta(
          index: index,
          id: nullIfBlank(entry.id),
          name: nullIfBlank(entry.name),
          argumentsFragment: fragment,
        ),
      ),
    );
  }

  void dispose() {
    if (_ownsTransport) _transport.dispose();
  }
}
