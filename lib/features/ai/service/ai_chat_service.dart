import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/ai_model_config.dart';
import 'ai_protocol_adapter.dart';

class AiChatService {
  AiChatService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _availabilityProbePrompt =
      'Reply with OK only if this model configuration works.';

  Future<String> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
      final blueprint = adapter.buildChatRequest(
        model: model,
        messages: messages,
      );
      final response = await _client
          .post(
            Uri.parse(blueprint.url),
            headers: blueprint.headers,
            body: jsonEncode(blueprint.body),
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorMessage = adapter.extractErrorMessage(response.body);
        throw AiChatException(
          'HTTP ${response.statusCode}${errorMessage.isEmpty ? '' : ': $errorMessage'}',
        );
      }
      try {
        return adapter.parseAssistantMessage(response.body);
      } on FormatException catch (error) {
        throw AiChatException(error.message);
      }
    } on TimeoutException {
      throw const AiChatException('Request timed out.');
    } on http.ClientException catch (error) {
      throw AiChatException(error.message);
    }
  }

  Future<String> testModel(AiModelConfig model) async {
    if (model.normalizedBaseUrl.isEmpty) {
      throw const AiChatException('Missing base URL.');
    }
    if (model.modelId.trim().isEmpty) {
      throw const AiChatException('Missing model ID.');
    }
    final reply = await sendMessage(
      model: model,
      messages: const [
        AiChatTurn(role: AiChatRole.user, content: _availabilityProbePrompt),
      ],
      timeout: const Duration(seconds: 20),
    );
    final normalizedReply = reply.trim();
    if (normalizedReply.isEmpty) {
      throw const AiChatException('Empty assistant reply.');
    }
    return normalizedReply;
  }

  void dispose() {
    _client.close();
  }
}

class AiChatException implements Exception {
  const AiChatException(this.message);

  final String message;

  @override
  String toString() => message;
}
