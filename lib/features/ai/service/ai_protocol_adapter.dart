import 'dart:convert';

import '../model/ai_model_config.dart';

enum AiChatRole { system, user, assistant }

class AiChatTurn {
  const AiChatTurn({required this.role, required this.content});

  final AiChatRole role;
  final String content;

  String get roleName {
    return switch (role) {
      AiChatRole.system => 'system',
      AiChatRole.user => 'user',
      AiChatRole.assistant => 'assistant',
    };
  }
}

class AiRequestBlueprint {
  const AiRequestBlueprint({
    required this.url,
    required this.headers,
    required this.body,
  });

  final String url;
  final Map<String, String> headers;
  final Map<String, Object?> body;
}

abstract class AiProtocolAdapter {
  const AiProtocolAdapter();

  AiProtocolType get protocolType;

  String get endpointPath;

  String describe(AiModelConfig model) {
    return '${protocolType.storageValue.toUpperCase()} · ${model.modelId}';
  }

  AiRequestBlueprint buildChatRequest({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
  }) {
    return AiRequestBlueprint(
      url: _buildUrl(model.normalizedBaseUrl, endpointPath, model.modelId),
      headers: buildHeaders(model),
      body: buildBody(model, messages),
    );
  }

  Map<String, String> buildHeaders(AiModelConfig model) {
    final headers = <String, String>{'content-type': 'application/json'};
    final rawToken = model.token.trim();
    if (rawToken.isEmpty || model.authScheme == AiAuthScheme.none) {
      return headers;
    }
    if (model.authScheme == AiAuthScheme.apiKey) {
      headers['x-api-key'] = model.authScheme.apply(rawToken);
      return headers;
    }
    headers['authorization'] = model.authScheme.apply(rawToken);
    return headers;
  }

  Map<String, Object?> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages,
  );

  String parseAssistantMessage(String rawResponse) {
    throw UnimplementedError(
      'parseAssistantMessage must be implemented by subclasses.',
    );
  }

  String extractErrorMessage(String rawResponse) {
    try {
      final decoded = jsonDecode(rawResponse);
      if (decoded is Map<String, Object?>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return error.trim();
        }
        if (error is Map<String, Object?>) {
          final message = '${error['message'] ?? ''}'.trim();
          if (message.isNotEmpty) {
            return message;
          }
        }
      }
    } catch (_) {
      // Fall through to the raw body.
    }
    return rawResponse.trim();
  }

  String _buildUrl(String baseUrl, String path, String modelId) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final baseUri = Uri.parse(baseUrl);
    final baseSegments = baseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final pathSegments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final overlapLength = _leadingPathOverlap(baseSegments, pathSegments);
    final remainingPath = pathSegments.skip(overlapLength).join('/');
    final joinedPath = remainingPath.isEmpty
        ? baseUrl
        : '$baseUrl/$remainingPath';
    return joinedPath.replaceAll('{model_id}', Uri.encodeComponent(modelId));
  }

  int _leadingPathOverlap(
    List<String> baseSegments,
    List<String> pathSegments,
  ) {
    final maxOverlap = baseSegments.length < pathSegments.length
        ? baseSegments.length
        : pathSegments.length;
    for (var length = maxOverlap; length > 0; length--) {
      final baseSuffix = baseSegments.skip(baseSegments.length - length);
      final pathPrefix = pathSegments.take(length);
      var matches = true;
      final baseIterator = baseSuffix.iterator;
      final pathIterator = pathPrefix.iterator;
      while (baseIterator.moveNext() && pathIterator.moveNext()) {
        if (baseIterator.current != pathIterator.current) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return length;
      }
    }
    return 0;
  }
}

class OpenAiProtocolAdapter extends AiProtocolAdapter {
  const OpenAiProtocolAdapter(this.protocolType);

  @override
  final AiProtocolType protocolType;

  @override
  String get endpointPath => 'v1/chat/completions';

  @override
  Map<String, Object?> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages,
  ) {
    return <String, Object?>{
      'model': model.modelId,
      'messages': messages
          .map(
            (item) => <String, Object?>{
              'role': item.roleName,
              'content': item.content,
            },
          )
          .toList(growable: false),
    };
  }

  @override
  String parseAssistantMessage(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Unexpected response payload.');
    }
    final choices = decoded['choices'];
    if (choices is! List<dynamic> || choices.isEmpty) {
      throw const FormatException('Missing response choices.');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map<String, Object?>) {
      throw const FormatException('Unexpected choice payload.');
    }
    final message = firstChoice['message'];
    if (message is! Map<String, Object?>) {
      throw const FormatException('Missing response message.');
    }
    return _extractOpenAiContent(message['content']);
  }
}

class ClaudeProtocolAdapter extends AiProtocolAdapter {
  const ClaudeProtocolAdapter();

  @override
  AiProtocolType get protocolType => AiProtocolType.claude;

  @override
  String get endpointPath => 'v1/messages';

  @override
  Map<String, String> buildHeaders(AiModelConfig model) {
    final headers = super.buildHeaders(model);
    headers.putIfAbsent('anthropic-version', () => '2023-06-01');
    return headers;
  }

  @override
  Map<String, Object?> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages,
  ) {
    return <String, Object?>{
      'model': model.modelId,
      'max_tokens': 1024,
      'messages': messages
          .where((item) => item.role != AiChatRole.system)
          .map(
            (item) => <String, Object?>{
              'role': item.role == AiChatRole.user ? 'user' : 'assistant',
              'content': item.content,
            },
          )
          .toList(growable: false),
    };
  }

  @override
  String parseAssistantMessage(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Unexpected response payload.');
    }
    final content = decoded['content'];
    if (content is! List<dynamic> || content.isEmpty) {
      throw const FormatException('Missing response content.');
    }
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final text = '${item['text'] ?? ''}'.trim();
      if (text.isEmpty) {
        continue;
      }
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.write(text);
    }
    final output = buffer.toString().trim();
    if (output.isEmpty) {
      throw const FormatException('Empty Claude response text.');
    }
    return output;
  }
}

class GeminiProtocolAdapter extends AiProtocolAdapter {
  const GeminiProtocolAdapter();

  @override
  AiProtocolType get protocolType => AiProtocolType.gemini;

  @override
  String get endpointPath => 'v1beta/models/{model_id}:generateContent';

  @override
  Map<String, String> buildHeaders(AiModelConfig model) {
    final headers = super.buildHeaders(model);
    headers.remove('authorization');
    headers.remove('x-api-key');
    if (model.token.trim().isNotEmpty &&
        model.authScheme == AiAuthScheme.apiKey) {
      headers['x-goog-api-key'] = model.token.trim();
    }
    return headers;
  }

  @override
  Map<String, Object?> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages,
  ) {
    return <String, Object?>{
      'contents': messages
          .map(
            (item) => <String, Object?>{
              'role': item.role == AiChatRole.assistant ? 'model' : 'user',
              'parts': <Map<String, Object?>>[
                <String, Object?>{'text': item.content},
              ],
            },
          )
          .toList(growable: false),
    };
  }

  @override
  String parseAssistantMessage(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Unexpected response payload.');
    }
    final candidates = decoded['candidates'];
    if (candidates is! List<dynamic> || candidates.isEmpty) {
      throw const FormatException('Missing response candidates.');
    }
    final firstCandidate = candidates.first;
    if (firstCandidate is! Map<String, Object?>) {
      throw const FormatException('Unexpected candidate payload.');
    }
    final content = firstCandidate['content'];
    if (content is! Map<String, Object?>) {
      throw const FormatException('Missing candidate content.');
    }
    final parts = content['parts'];
    if (parts is! List<dynamic> || parts.isEmpty) {
      throw const FormatException('Missing Gemini response parts.');
    }
    final buffer = StringBuffer();
    for (final item in parts) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final text = '${item['text'] ?? ''}'.trim();
      if (text.isEmpty) {
        continue;
      }
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.write(text);
    }
    final output = buffer.toString().trim();
    if (output.isEmpty) {
      throw const FormatException('Empty Gemini response text.');
    }
    return output;
  }
}

abstract final class AiProtocolRegistry {
  static final Map<AiProtocolType, AiProtocolAdapter> _adapters =
      <AiProtocolType, AiProtocolAdapter>{
        AiProtocolType.openai: const OpenAiProtocolAdapter(
          AiProtocolType.openai,
        ),
        AiProtocolType.deepseek: const OpenAiProtocolAdapter(
          AiProtocolType.deepseek,
        ),
        AiProtocolType.kimi: const OpenAiProtocolAdapter(AiProtocolType.kimi),
        AiProtocolType.glm: const OpenAiProtocolAdapter(AiProtocolType.glm),
        AiProtocolType.grok: const OpenAiProtocolAdapter(AiProtocolType.grok),
        AiProtocolType.claude: const ClaudeProtocolAdapter(),
        AiProtocolType.gemini: const GeminiProtocolAdapter(),
      };

  static AiProtocolAdapter adapterFor(AiProtocolType protocolType) {
    return _adapters[protocolType] ??
        const OpenAiProtocolAdapter(AiProtocolType.openai);
  }
}

String _extractOpenAiContent(Object? rawContent) {
  if (rawContent is String && rawContent.trim().isNotEmpty) {
    return rawContent.trim();
  }
  if (rawContent is List<dynamic>) {
    final buffer = StringBuffer();
    for (final item in rawContent) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final text = '${item['text'] ?? ''}'.trim();
      if (text.isEmpty) {
        continue;
      }
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.write(text);
    }
    final output = buffer.toString().trim();
    if (output.isNotEmpty) {
      return output;
    }
  }
  throw const FormatException('Empty OpenAI-compatible response text.');
}
