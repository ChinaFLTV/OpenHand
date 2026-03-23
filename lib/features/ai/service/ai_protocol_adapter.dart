import 'dart:convert';

import '../model/ai_model_config.dart';
import '../model/ai_token_usage.dart';

enum AiChatRole { system, user, assistant, tool }

class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final String arguments;

  Map<String, Object?> toOpenAiJson() {
    return <String, Object?>{
      'id': id,
      'type': 'function',
      'function': <String, Object?>{'name': name, 'arguments': arguments},
    };
  }
}

class AiToolDefinition {
  const AiToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;

  Map<String, Object?> toOpenAiJson() {
    return <String, Object?>{
      'type': 'function',
      'function': <String, Object?>{
        'name': name,
        'description': description,
        'parameters': parameters,
      },
    };
  }
}

class AiChatTurn {
  const AiChatTurn({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolCalls = const <AiToolCall>[],
  });

  final AiChatRole role;
  final String content;
  final String? toolCallId;
  final List<AiToolCall> toolCalls;

  String get roleName {
    return switch (role) {
      AiChatRole.system => 'system',
      AiChatRole.user => 'user',
      AiChatRole.assistant => 'assistant',
      AiChatRole.tool => 'tool',
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

  String get streamEndpointPath => endpointPath;

  bool get supportsServerStreaming => false;

  bool get supportsToolCalls => false;

  String describe(AiModelConfig model) {
    return '${protocolType.storageValue.toUpperCase()} · ${model.modelId}';
  }

  AiRequestBlueprint buildChatRequest({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    bool stream = false,
  }) {
    return AiRequestBlueprint(
      url: _buildUrl(
        model.normalizedBaseUrl,
        stream ? streamEndpointPath : endpointPath,
        model.modelId,
      ),
      headers: buildHeaders(model),
      body: buildBody(model, messages, tools: tools, stream: stream),
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
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    bool stream = false,
  });

  AiTokenUsage? parseUsage(String rawResponse) {
    return null;
  }

  List<AiToolCall> parseToolCalls(String rawResponse) {
    return const <AiToolCall>[];
  }

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
    final pathParts = path.split('?');
    final normalizedPath = pathParts.first.startsWith('/')
        ? pathParts.first.substring(1)
        : pathParts.first;
    final queryString = pathParts.length > 1
        ? pathParts.sublist(1).join('?')
        : '';
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
    final resolvedPath = joinedPath.replaceAll(
      '{model_id}',
      Uri.encodeComponent(modelId),
    );
    if (queryString.isEmpty) {
      return resolvedPath;
    }
    return '$resolvedPath?$queryString';
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
  bool get supportsServerStreaming => true;

  @override
  bool get supportsToolCalls => true;

  @override
  Map<String, Object?> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    bool stream = false,
  }) {
    return <String, Object?>{
      'model': model.modelId,
      if (stream) 'stream': true,
      if (stream) 'stream_options': <String, Object?>{'include_usage': true},
      if (tools.isNotEmpty)
        'tools': tools
            .map((item) => item.toOpenAiJson())
            .toList(growable: false),
      if (tools.isNotEmpty) 'tool_choice': 'auto',
      'messages': messages
          .map((item) => _mapOpenAiMessage(item))
          .toList(growable: false),
    };
  }

  Map<String, Object?> _mapOpenAiMessage(AiChatTurn item) {
    final payload = <String, Object?>{'role': item.roleName};
    if (item.role == AiChatRole.tool) {
      payload['tool_call_id'] = item.toolCallId ?? '';
      payload['content'] = item.content;
      return payload;
    }
    payload['content'] = item.content;
    if (item.role == AiChatRole.assistant && item.toolCalls.isNotEmpty) {
      payload['tool_calls'] = item.toolCalls
          .map((toolCall) => toolCall.toOpenAiJson())
          .toList(growable: false);
    }
    return payload;
  }

  @override
  AiTokenUsage? parseUsage(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final usage = decoded['usage'];
    if (usage is! Map && usage is! Map<String, Object?>) {
      return null;
    }
    final usageMap = usage is Map<String, Object?>
        ? usage
        : Map<String, Object?>.from(usage as Map);
    return AiTokenUsage(
      promptTokens: _readInt(usageMap['prompt_tokens']),
      completionTokens: _readInt(usageMap['completion_tokens']),
      totalTokens: _readInt(usageMap['total_tokens']),
    );
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

  @override
  List<AiToolCall> parseToolCalls(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return const <AiToolCall>[];
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      return const <AiToolCall>[];
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      return const <AiToolCall>[];
    }
    final message = firstChoice['message'];
    if (message is! Map) {
      return const <AiToolCall>[];
    }
    final toolCalls = message['tool_calls'];
    if (toolCalls is! List) {
      return const <AiToolCall>[];
    }
    return toolCalls
        .map((item) {
          if (item is! Map) {
            return null;
          }
          final toolCallMap = Map<String, Object?>.from(item);
          final function = toolCallMap['function'];
          if (function is! Map) {
            return null;
          }
          final functionMap = Map<String, Object?>.from(function);
          final id = '${toolCallMap['id'] ?? ''}'.trim();
          final name = '${functionMap['name'] ?? ''}'.trim();
          if (id.isEmpty || name.isEmpty) {
            return null;
          }
          return AiToolCall(
            id: id,
            name: name,
            arguments: '${functionMap['arguments'] ?? ''}',
          );
        })
        .whereType<AiToolCall>()
        .toList(growable: false);
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
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    bool stream = false,
  }) {
    final systemContent = messages
        .where((item) => item.role == AiChatRole.system)
        .map((item) => item.content.trim())
        .where((item) => item.isNotEmpty)
        .join('\n\n');
    return <String, Object?>{
      'model': model.modelId,
      if (systemContent.isNotEmpty) 'system': systemContent,
      'max_tokens': 1024,
      if (stream) 'stream': true,
      'messages': messages
          .where((item) => item.role != AiChatRole.system)
          .where((item) => item.role != AiChatRole.tool)
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
  AiTokenUsage? parseUsage(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final usage = decoded['usage'];
    if (usage is! Map && usage is! Map<String, Object?>) {
      return null;
    }
    final usageMap = usage is Map<String, Object?>
        ? usage
        : Map<String, Object?>.from(usage as Map);
    final promptTokens = _readInt(usageMap['input_tokens']);
    final completionTokens = _readInt(usageMap['output_tokens']);
    return AiTokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens:
          _readInt(usageMap['total_tokens']) ??
          ((promptTokens ?? 0) + (completionTokens ?? 0)),
    );
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
  String get streamEndpointPath =>
      'v1beta/models/{model_id}:streamGenerateContent?alt=sse';

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
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    bool stream = false,
  }) {
    final systemContent = messages
        .where((item) => item.role == AiChatRole.system)
        .map((item) => item.content.trim())
        .where((item) => item.isNotEmpty)
        .join('\n\n');
    return <String, Object?>{
      if (systemContent.isNotEmpty)
        'systemInstruction': <String, Object?>{
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': systemContent},
          ],
        },
      'contents': messages
          .where((item) => item.role != AiChatRole.system)
          .where((item) => item.role != AiChatRole.tool)
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
  AiTokenUsage? parseUsage(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final usage = decoded['usageMetadata'];
    if (usage is! Map && usage is! Map<String, Object?>) {
      return null;
    }
    final usageMap = usage is Map<String, Object?>
        ? usage
        : Map<String, Object?>.from(usage as Map);
    return AiTokenUsage(
      promptTokens: _readInt(usageMap['promptTokenCount']),
      completionTokens: _readInt(usageMap['candidatesTokenCount']),
      totalTokens: _readInt(usageMap['totalTokenCount']),
    );
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
    return _adapters[protocolType] ?? _adapters[AiProtocolType.openai]!;
  }
}

String _extractOpenAiContent(Object? rawContent) {
  if (rawContent is String && rawContent.trim().isNotEmpty) {
    return rawContent.trim();
  }
  if (rawContent is List<dynamic>) {
    final buffer = StringBuffer();
    for (final item in rawContent) {
      if (item is String && item.trim().isNotEmpty) {
        if (buffer.isNotEmpty) {
          buffer.writeln();
        }
        buffer.write(item.trim());
        continue;
      }
      if (item is! Map<String, Object?>) {
        continue;
      }
      final text = '${item['text'] ?? item['content'] ?? ''}'.trim();
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
  throw const FormatException('Empty assistant response text.');
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    final coercedValue = value.toInt();
    return value == coercedValue ? coercedValue : null;
  }
  final rawText = '${value ?? ''}'.trim();
  if (rawText.isEmpty) {
    return null;
  }
  final parsedInt = int.tryParse(rawText);
  if (parsedInt != null) {
    return parsedInt;
  }
  final parsedDouble = double.tryParse(rawText);
  if (parsedDouble == null) {
    return null;
  }
  final coercedValue = parsedDouble.toInt();
  return parsedDouble == coercedValue ? coercedValue : null;
}
