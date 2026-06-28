import 'dart:async';

import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../chat/ai_chat_service.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import '../session_io/ai_token_usage_parser.dart';
import 'ai_operation_http.dart';

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
    this.requestUrl,
    this.requestMethod,
    this.requestHeaders,
    this.requestBody,
  });

  final String text;
  final String rawResponse;
  final String? reasoning;
  final AiTokenUsage? usage;
  final String? requestUrl;
  final String? requestMethod;
  final Map<String, String>? requestHeaders;
  final Map<String, Object?>? requestBody;
}

class AiResponsesService {
  AiResponsesService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient();

  final AiEndpointRouter _router;
  final AiTransportClient _transport;

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
  }) {
    const family = AiApiFamily.responses;
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
    );
    final body =
        AiOperationHttp.mergeBodyExtras(model, family, <String, Object?>{
          'model': model.resolveOperationModelId(family),
          'input': input,
          if (instructions?.trim().isNotEmpty == true)
            'instructions': instructions!.trim(),
          if (previousResponseId?.trim().isNotEmpty == true)
            'previous_response_id': previousResponseId!.trim(),
          if (store != null) 'store': store,
          if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
          if (temperature != null && temperature.isFinite)
            'temperature': temperature,
          if (temperature == null && model.temperature != null)
            'temperature': model.temperature,
          if (maxOutputTokens != null && maxOutputTokens > 0)
            'max_output_tokens': maxOutputTokens,
          if (maxOutputTokens == null && model.maxTokens != null)
            'max_output_tokens': model.maxTokens,
          if (topP != null && topP.isFinite) 'top_p': topP,
          if (reasoning != null) 'reasoning': reasoning,
          if (text != null) 'text': text,
          if (tools != null) 'tools': tools,
          if (toolChoice != null) 'tool_choice': toolChoice,
          if (user?.trim().isNotEmpty == true) 'user': user!.trim(),
          if (stream) 'stream': true,
        });
    return AiResponsesRequestBlueprint(
      url: AiOperationHttp.uriWithExtraQuery(
        endpoint.url,
        model,
        family,
      ).toString(),
      method: endpoint.method,
      headers: AiOperationHttp.buildHeaders(
        model: model,
        endpointHeaders: endpoint.headers,
        family: family,
      ),
      body: body,
    );
  }

  Future<AiResponsesResult> createResponse({
    required AiModelConfig model,
    required Object input,
    Duration timeout = const Duration(seconds: 60),
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
  }) async {
    final request = buildRequest(
      model: model,
      input: input,
      instructions: instructions,
      previousResponseId: previousResponseId,
      store: store,
      metadata: metadata,
      temperature: temperature,
      maxOutputTokens: maxOutputTokens,
      topP: topP,
      reasoning: reasoning,
      text: text,
      tools: tools,
      toolChoice: toolChoice,
      user: user,
    );
    final response = await _transport.sendJson(
      uri: Uri.parse(request.url),
      method: request.method,
      headers: request.headers,
      body: request.body,
      timeout: timeout,
    );
    AiOperationHttp.throwIfFailed(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'responses',
    );
    final decoded = AiOperationHttp.decodeJsonResponse(
      response.body,
      contextHint: 'responses',
    );
    final parsed = _parseResponsePayload(decoded);
    return AiResponsesResult(
      text: parsed.text,
      rawResponse: response.body,
      reasoning: parsed.reasoning,
      usage: parsed.usage,
      requestUrl: request.url,
      requestMethod: request.method,
      requestHeaders: Map<String, String>.unmodifiable(request.headers),
      requestBody: request.body,
    );
  }

  _ParsedResponsesPayload _parseResponsePayload(Object? decoded) {
    var text = '';
    String? reasoning;
    AiTokenUsage? usage;
    if (decoded is Map<String, Object?>) {
      final directText = '${decoded['output_text'] ?? decoded['text'] ?? ''}'
          .trim();
      if (directText.isNotEmpty) {
        text = directText;
      }
      final output = decoded['output'];
      if (output is List) {
        final buffer = StringBuffer();
        final reasoningBuffer = StringBuffer();
        for (final item in output) {
          if (item is! Map) continue;
          final itemType = '${item['type'] ?? ''}'.trim();
          if (itemType == 'reasoning') {
            _appendResponseText(reasoningBuffer, item['summary']);
            _appendResponseText(reasoningBuffer, item['content']);
            continue;
          }
          final content = item['content'];
          if (content is! List) {
            if (itemType == 'message') {
              _appendResponseText(buffer, content);
            }
            continue;
          }
          for (final part in content) {
            if (part is! Map) continue;
            final type = '${part['type'] ?? ''}'.trim();
            if (type == 'output_text') {
              _appendResponseText(buffer, part['text']);
            }
            if (type == 'text') {
              _appendResponseText(buffer, part['text']);
            }
            if (type == 'reasoning') {
              _appendResponseText(
                reasoningBuffer,
                part['summary'] ?? part['text'],
              );
            }
          }
        }
        final parsedText = buffer.toString().trim();
        if (parsedText.isNotEmpty) {
          text = parsedText;
        }
        final normalizedReasoning = reasoningBuffer.toString().trim();
        reasoning = normalizedReasoning.isEmpty ? null : normalizedReasoning;
      }
      if (text.isEmpty) {
        text = _parseChatChoiceText(decoded);
      }
      final usageMap = decoded['usage'];
      if (usageMap is Map<String, Object?>) {
        usage = AiTokenUsageParser.parseOpenAi(usageMap);
      } else if (usageMap is Map) {
        usage = AiTokenUsageParser.parseOpenAi(
          stringKeyedMapFromValue(usageMap),
        );
      }
    }
    return _ParsedResponsesPayload(
      text: text,
      reasoning: reasoning,
      usage: usage,
    );
  }

  String _parseChatChoiceText(Map<String, Object?> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return '';
    }
    final choice = stringKeyedMapFromValue(choices.first);
    final message = choice['message'];
    if (message is Map) {
      final content = message['content'];
      if (content is String) return content.trim();
      if (content is List) {
        return content
            .whereType<Map>()
            .map((item) => '${item['text'] ?? ''}'.trim())
            .where((item) => item.isNotEmpty)
            .join('\n')
            .trim();
      }
    }
    return '${choice['text'] ?? ''}'.trim();
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
      final direct = value['text'] ?? value['summary'] ?? value['content'];
      final text = _responseTextValue(direct);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  void parseSseEvent(
    Map<String, Object?> decoded, {
    required StringBuffer textBuffer,
    required StringBuffer reasoningBuffer,
    required AiTokenUsage? Function() usage,
    required void Function(AiTokenUsage?) setUsage,
    required void Function(AiChatStreamEvent) emitEvent,
    required void Function(String) setFinishReason,
  }) {
    final type = '${decoded['type'] ?? ''}'.trim();
    if (type == 'response.output_text.delta') {
      final delta = '${decoded['delta'] ?? ''}';
      if (delta.isNotEmpty) {
        textBuffer.write(delta);
        emitEvent(AiChatStreamEvent.textDelta(delta));
      }
      return;
    }
    if (type == 'response.reasoning.delta') {
      final delta = '${decoded['delta'] ?? ''}';
      if (delta.isNotEmpty) {
        reasoningBuffer.write(delta);
        emitEvent(AiChatStreamEvent.reasoningDelta(delta));
      }
      return;
    }
    if (type == 'response.completed') {
      final response = decoded['response'];
      if (response is Map<String, Object?>) {
        final parsed = _parseResponsePayload(response);
        final currentText = textBuffer.toString().trim();
        if (currentText.isEmpty && parsed.text.isNotEmpty) {
          textBuffer.write(parsed.text);
        }
        final currentReasoning = reasoningBuffer.toString().trim();
        final parsedReasoning = parsed.reasoning;
        if (currentReasoning.isEmpty &&
            parsedReasoning != null &&
            parsedReasoning.isNotEmpty) {
          reasoningBuffer.write(parsedReasoning);
        }
        final parsedUsage = parsed.usage;
        if (parsedUsage != null && !parsedUsage.isEmpty) {
          setUsage(parsedUsage);
          emitEvent(AiChatStreamEvent.usage(parsedUsage));
        }
      }
      setFinishReason('stop');
      return;
    }
    if (type == 'response.failed') {
      setFinishReason('error');
      return;
    }
  }

  void dispose() {
    _transport.dispose();
  }
}

class _ParsedResponsesPayload {
  const _ParsedResponsesPayload({
    required this.text,
    this.reasoning,
    this.usage,
  });

  final String text;
  final String? reasoning;
  final AiTokenUsage? usage;
}
