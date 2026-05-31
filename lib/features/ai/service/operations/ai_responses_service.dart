import 'dart:async';
import 'dart:convert';

import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../chat/ai_chat_service.dart';
import '../chat/ai_transport_diagnostic_messages.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import '../session_io/ai_token_usage_parser.dart';

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
    required String input,
    bool stream = false,
  }) {
    final endpoint = _router.resolve(
      model,
      AiApiFamily.responses,
      method: model.requestMethod,
    );
    final headers = <String, String>{
      'content-type': 'application/json',
      ...model.customHeaders,
      ...endpoint.headers,
    };
    final token = model.token.trim();
    if (token.isNotEmpty && model.authScheme != AiAuthScheme.none) {
      if (model.authScheme == AiAuthScheme.apiKey) {
        headers['x-api-key'] = model.authScheme.apply(token);
      } else {
        headers['authorization'] = model.authScheme.apply(token);
      }
    }
    final body = <String, Object?>{
      'model': model.resolveOperationModelId(AiApiFamily.responses),
      'input': input,
      if (stream) 'stream': true,
    };
    return AiResponsesRequestBlueprint(
      url: endpoint.url,
      method: endpoint.method,
      headers: headers,
      body: body,
    );
  }

  Future<AiResponsesResult> createResponse({
    required AiModelConfig model,
    required String input,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final request = buildRequest(model: model, input: input);
    final response = await _transport.sendJson(
      uri: Uri.parse(request.url),
      method: request.method,
      headers: request.headers,
      body: request.body,
      timeout: timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        AiTransportDiagnosticMessages.httpStatus(
          response.statusCode,
          serverMessage: response.body,
          contextHint: 'responses',
        ),
      );
    }
    final decoded = jsonDecode(response.body);
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
      final output = decoded['output'];
      if (output is List) {
        final buffer = StringBuffer();
        final reasoningBuffer = StringBuffer();
        for (final item in output) {
          if (item is! Map) continue;
          final content = item['content'];
          if (content is! List) continue;
          for (final part in content) {
            if (part is! Map) continue;
            final type = '${part['type'] ?? ''}'.trim();
            if (type == 'output_text') {
              final partText = '${part['text'] ?? ''}'.trim();
              if (partText.isNotEmpty) {
                if (buffer.isNotEmpty) buffer.writeln();
                buffer.write(partText);
              }
            }
            if (type == 'reasoning') {
              final partText = '${part['summary'] ?? part['text'] ?? ''}'.trim();
              if (partText.isNotEmpty) {
                if (reasoningBuffer.isNotEmpty) reasoningBuffer.writeln();
                reasoningBuffer.write(partText);
              }
            }
          }
        }
        text = buffer.toString().trim();
        final normalizedReasoning = reasoningBuffer.toString().trim();
        reasoning = normalizedReasoning.isEmpty ? null : normalizedReasoning;
      }
      final usageMap = decoded['usage'];
      if (usageMap is Map<String, Object?>) {
        usage = AiTokenUsageParser.parseOpenAi(usageMap);
      } else if (usageMap is Map) {
        usage = AiTokenUsageParser.parseOpenAi(
          Map<String, Object?>.from(usageMap),
        );
      }
    }
    return _ParsedResponsesPayload(text: text, reasoning: reasoning, usage: usage);
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
