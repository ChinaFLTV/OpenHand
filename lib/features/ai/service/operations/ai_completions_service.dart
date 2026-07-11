import 'dart:async';

import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_model_config.dart';
import '../runtime/ai_endpoint_router.dart';
import '../runtime/ai_transport_client.dart';
import 'ai_operation_http.dart';

class AiCompletionResult {
  const AiCompletionResult({
    required this.text,
    required this.rawResponse,
    this.payload = const <String, Object?>{},
  });

  final String text;
  final String rawResponse;
  final Map<String, Object?> payload;
}

class AiCompletionsService {
  AiCompletionsService({AiEndpointRouter? router, AiTransportClient? transport})
    : _router = router ?? const AiEndpointRouter(),
      _transport = transport ?? AiTransportClient(),
      _ownsTransport = transport == null;

  final AiEndpointRouter _router;
  final AiTransportClient _transport;
  final bool _ownsTransport;

  Future<AiCompletionResult> complete({
    required AiModelConfig model,
    required Object prompt,
    Duration timeout = AiOperationHttp.defaultRequestTimeout,
    String? suffix,
    int? maxTokens,
    double? temperature,
    double? topP,
    int? n,
    Object? stop,
    bool? stream,
    int? logprobs,
    bool? echo,
    double? presencePenalty,
    double? frequencyPenalty,
    String? user,
  }) async {
    const family = AiApiFamily.completions;
    final suffixValue = nullIfBlank(suffix);
    final userValue = nullIfBlank(user);
    final endpoint = _router.resolve(
      model,
      family,
      method: model.requestMethod,
    );
    final body =
        AiOperationHttp.mergeBodyExtras(model, family, <String, Object?>{
          'model': model.resolveOperationModelId(family),
          'prompt': prompt,
          if (suffixValue != null) 'suffix': suffixValue,
          if (maxTokens != null && maxTokens > 0) 'max_tokens': maxTokens,
          if (maxTokens == null && model.maxTokens != null)
            'max_tokens': model.maxTokens,
          if (temperature != null && temperature.isFinite)
            'temperature': temperature,
          if (temperature == null && model.temperature != null)
            'temperature': model.temperature,
          if (topP != null && topP.isFinite) 'top_p': topP,
          if (n != null && n > 0) 'n': n,
          if (stop != null) 'stop': stop,
          if (stream != null) 'stream': stream,
          if (logprobs != null && logprobs >= 0) 'logprobs': logprobs,
          if (echo != null) 'echo': echo,
          if (presencePenalty != null && presencePenalty.isFinite)
            'presence_penalty': presencePenalty,
          if (frequencyPenalty != null && frequencyPenalty.isFinite)
            'frequency_penalty': frequencyPenalty,
          if (userValue != null) 'user': userValue,
        });
    final response = await AiOperationHttp.sendJsonForFamily(
      transport: _transport,
      endpoint: endpoint,
      model: model,
      family: family,
      body: body,
      timeout: timeout,
    );
    final payload = AiOperationHttp.decodeSuccessfulJsonMap(
      statusCode: response.statusCode,
      body: response.body,
      contextHint: 'completions',
    );
    final choices = payload['choices'];
    String text = '';
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final choice = stringKeyedMapFromValue(choices.first);
      text = '${choice['text'] ?? ''}'.trim();
      if (text.isEmpty && choice['message'] is Map) {
        final message = stringKeyedMapFromValue(choice['message']);
        text = '${message['content'] ?? ''}'.trim();
      }
    }
    return AiCompletionResult(
      text: text,
      rawResponse: response.body,
      payload: payload,
    );
  }

  void dispose() {
    if (_ownsTransport) {
      _transport.dispose();
    }
  }
}
