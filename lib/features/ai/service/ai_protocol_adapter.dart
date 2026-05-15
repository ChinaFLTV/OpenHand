import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../model/ai_input_cache_runtime_config.dart';
import '../model/ai_model_config.dart';
import '../model/ai_token_usage.dart';
import 'ai_token_usage_parser.dart';

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

  /// Claude/Anthropic tool format: top-level `name`, `description`,
  /// `input_schema` (identical content to OpenAI `parameters`).
  Map<String, Object?> toClaudeJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'input_schema': parameters,
    };
  }
}

enum AiChatContentPartKind { text, imageFile }

class AiChatContentPart {
  const AiChatContentPart._({
    required this.kind,
    this.text,
    this.filePath,
    this.mimeType,
  });

  const AiChatContentPart.text(String value)
    : this._(kind: AiChatContentPartKind.text, text: value);

  const AiChatContentPart.imageFile({
    required String filePath,
    required String mimeType,
  }) : this._(
         kind: AiChatContentPartKind.imageFile,
         filePath: filePath,
         mimeType: mimeType,
       );

  final AiChatContentPartKind kind;
  final String? text;
  final String? filePath;
  final String? mimeType;
}

class AiChatTurn {
  const AiChatTurn({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolCalls = const <AiToolCall>[],
    this.parts = const <AiChatContentPart>[],
    this.reasoningContent,
  });

  final AiChatRole role;
  final String content;
  final String? toolCallId;
  final List<AiToolCall> toolCalls;
  final List<AiChatContentPart> parts;

  /// Echo-back chain-of-thought captured from the previous turn. Required by
  /// some thinking-mode gateways (e.g. the `deepseek-v4-pro` family that
  /// rejects the request with HTTP 400 "The 'reasoning_content' in the
  /// thinking mode must be passed back to the API" when omitted) and harmless
  /// for providers that ignore the field. Only meaningful for assistant role
  /// turns.
  final String? reasoningContent;

  AiChatTurn copyWith({String? reasoningContent}) {
    return AiChatTurn(
      role: role,
      content: content,
      toolCallId: toolCallId,
      toolCalls: toolCalls,
      parts: parts,
      reasoningContent: reasoningContent ?? this.reasoningContent,
    );
  }

  String get roleName {
    return switch (role) {
      AiChatRole.system => 'system',
      AiChatRole.user => 'user',
      AiChatRole.assistant => 'assistant',
      AiChatRole.tool => 'tool',
    };
  }

  List<AiChatContentPart> get effectiveParts {
    final normalizedContent = content.trim();
    if (normalizedContent.isEmpty) {
      return parts;
    }
    return <AiChatContentPart>[AiChatContentPart.text(content), ...parts];
  }

  int get promptCharacterCount {
    var total = content.length;
    for (final part in parts) {
      total += switch (part.kind) {
        AiChatContentPartKind.text => part.text?.length ?? 0,
        AiChatContentPartKind.imageFile => 64,
      };
    }
    return total;
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

  Future<AiRequestBlueprint> buildChatRequest({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    return AiRequestBlueprint(
      url: _buildUrl(
        model.normalizedBaseUrl,
        stream ? streamEndpointPath : endpointPath,
        model.modelId,
      ),
      headers: buildHeaders(model),
      body: await buildBody(
        model,
        messages,
        tools: tools,
        responseModalities: responseModalities,
        stream: stream,
        inputCacheConfig: inputCacheConfig,
      ),
    );
  }

  Map<String, String> buildHeaders(AiModelConfig model) {
    final headers = <String, String>{'content-type': 'application/json'};
    final rawToken = model.token.trim();
    if (rawToken.isEmpty || model.authScheme == AiAuthScheme.none) {
      // Apply custom headers from provider config.
      _mergeCustomHeaders(headers, model);
      return headers;
    }
    if (model.authScheme == AiAuthScheme.apiKey) {
      headers['x-api-key'] = model.authScheme.apply(rawToken);
      _mergeCustomHeaders(headers, model);
      return headers;
    }
    headers['authorization'] = model.authScheme.apply(rawToken);
    _mergeCustomHeaders(headers, model);
    return headers;
  }

  /// Merges user-defined custom headers from [model.customHeaders] into the
  /// [headers] map. Custom headers are applied last so they can override
  /// previously set values (e.g. content-type, authorization).
  void _mergeCustomHeaders(Map<String, String> headers, AiModelConfig model) {
    if (model.customHeaders.isEmpty) return;
    for (final entry in model.customHeaders.entries) {
      final key = entry.key.trim();
      if (key.isNotEmpty) {
        headers[key] = entry.value;
      }
    }
  }

  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  });

  bool supportsAttachmentsForModel(AiModelConfig model) {
    // Check user-configured profile override first.
    final profileOverride = model.profileFor(model.modelId).isMultimodal;
    if (profileOverride != null) return profileOverride;
    return false;
  }

  AiTokenUsage? parseUsage(String rawResponse) {
    return null;
  }

  List<AiToolCall> parseToolCalls(String rawResponse) {
    return const <AiToolCall>[];
  }

  Future<String> encodeFileAsDataUrl({
    required String filePath,
    required String mimeType,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  Future<String> parseAssistantMessage(String rawResponse) {
    throw UnimplementedError(
      'parseAssistantMessage must be implemented by subclasses.',
    );
  }

  String extractErrorMessage(String rawResponse) {
    final trimmed = rawResponse.trim();
    // Try JSON error first.
    try {
      final decoded = jsonDecode(trimmed);
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
      // Not JSON — may be HTML or plain text.
    }
    // Strip HTML tags for cleaner display when the server returns an HTML
    // error page (e.g. nginx 400/502 pages).
    if (trimmed.contains('<html') || trimmed.contains('<HTML')) {
      final stripped = trimmed
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return stripped.isEmpty ? trimmed : stripped;
    }
    return trimmed;
  }

  String _buildUrl(String baseUrl, String path, String modelId) {
    final pathParts = path.split('?');
    final normalizedPath = pathParts.first.startsWith('/')
        ? pathParts.first.substring(1)
        : pathParts.first;
    // Endpoint paths conventionally contain at most one `?`. If a caller
    // accidentally embeds multiple `?` segments, treat the trailing ones
    // as additional query pairs (the HTTP spec only honours the first
    // `?` as the query delimiter; subsequent `?` are literal characters
    // inside the query string), and stitch them with `&`.
    final endpointQuery = pathParts.length > 1
        ? pathParts.sublist(1).join('&')
        : '';
    final baseUri = Uri.parse(baseUrl);
    final baseSegments = baseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final pathSegments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map((segment) => segment.replaceAll('{model_id}', modelId))
        .toList(growable: false);
    final overlapLength = _leadingPathOverlap(baseSegments, pathSegments);
    final mergedPathSegments = <String>[
      ...baseSegments,
      ...pathSegments.skip(overlapLength),
    ];
    final mergedQuery = _mergeQueryStrings(baseUri.query, endpointQuery);
    return Uri(
      scheme: baseUri.scheme,
      userInfo: baseUri.userInfo.isEmpty ? null : baseUri.userInfo,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      pathSegments: mergedPathSegments,
      query: mergedQuery.isEmpty ? null : mergedQuery,
    ).toString();
  }

  String _mergeQueryStrings(String baseQuery, String endpointQuery) {
    if (baseQuery.isEmpty) {
      return endpointQuery;
    }
    if (endpointQuery.isEmpty) {
      return baseQuery;
    }
    return '$baseQuery&$endpointQuery';
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
  const OpenAiProtocolAdapter(
    this.protocolType, {
    this.visionModelPatterns = const <String>[],
  });

  @override
  final AiProtocolType protocolType;

  /// Substring patterns used to detect whether a model ID supports inline
  /// image attachments. If a model ID contains any of these patterns
  /// (case-insensitive), the adapter treats it as vision-capable.
  final List<String> visionModelPatterns;

  @override
  String get endpointPath => 'v1/chat/completions';

  @override
  bool get supportsServerStreaming => true;

  @override
  bool get supportsToolCalls => true;

  @override
  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    final requestMessages = await Future.wait<Map<String, Object?>>(
      messages.map((item) => _mapOpenAiMessage(item)),
    );
    // Many OpenAI-compatible providers reject requests with multiple system
    // messages.  Merge consecutive leading system messages into one to
    // maximise compatibility while keeping the prompt structure intact.
    final mergedMessages = _mergeConsecutiveSystemMessages(requestMessages);
    return <String, Object?>{
      'model': model.modelId,
      if (model.maxTokens != null) 'max_tokens': model.maxTokens,
      if (model.temperature != null) 'temperature': model.temperature,
      if (stream) 'stream': true,
      // Some OpenAI-compatible providers (DeepSeek / Kimi / GLM / Doubao /
      // Grok / Qwen / Hunyuan / Wenxin / Stepfun / MiniMax / LongCat 等) only
      // emit the trailing `usage` chunk—including cache hit/write fields—
      // when `stream_options.include_usage` is explicitly requested. Always
      // opt in for streaming so the token popup gets full cache stats.
      if (stream)
        'stream_options': const <String, Object?>{'include_usage': true},
      if (tools.isNotEmpty)
        'tools': tools
            .map((item) => item.toOpenAiJson())
            .toList(growable: false),
      if (tools.isNotEmpty) 'tool_choice': 'auto',
      'messages': mergedMessages,
    };
  }

  @override
  bool supportsAttachmentsForModel(AiModelConfig model) {
    final profileOverride = model.profileFor(model.modelId).isMultimodal;
    if (profileOverride != null) return profileOverride;
    return _containsAny(model.modelId, visionModelPatterns);
  }

  Future<Map<String, Object?>> _mapOpenAiMessage(AiChatTurn item) async {
    final payload = <String, Object?>{'role': item.roleName};
    if (item.role == AiChatRole.tool) {
      payload['tool_call_id'] = item.toolCallId ?? '';
      payload['content'] = item.content;
      return payload;
    }
    final contentParts = item.effectiveParts;
    if (contentParts.isNotEmpty &&
        contentParts.any((part) => part.kind != AiChatContentPartKind.text)) {
      payload['content'] = await _mapOpenAiContentParts(contentParts);
    } else {
      payload['content'] = contentParts.isEmpty
          ? item.content
          : contentParts.map((part) => part.text ?? '').join('\n\n').trim();
    }
    if (item.role == AiChatRole.assistant && item.toolCalls.isNotEmpty) {
      payload['tool_calls'] = item.toolCalls
          .map((toolCall) => toolCall.toOpenAiJson())
          .toList(growable: false);
    }
    if (item.role == AiChatRole.assistant) {
      final reasoning = item.reasoningContent;
      if (reasoning != null && reasoning.isNotEmpty) {
        // Some thinking-mode providers (notably the `deepseek-v4-pro`
        // family routed via OpenAI-compatible gateways) reject follow-up
        // requests with HTTP 400 "The 'reasoning_content' in the thinking
        // mode must be passed back to the API" if the prior assistant
        // chain-of-thought is dropped. Echoing the reasoning here is
        // ignored by providers that don't expect it (per the OpenAI
        // schema unknown fields are tolerated).
        payload['reasoning_content'] = reasoning;
      }
    }
    return payload;
  }

  Future<List<Map<String, Object?>>> _mapOpenAiContentParts(
    List<AiChatContentPart> parts,
  ) async {
    final payload = <Map<String, Object?>>[];
    for (final part in parts) {
      switch (part.kind) {
        case AiChatContentPartKind.text:
          final text = (part.text ?? '').trim();
          if (text.isEmpty) {
            continue;
          }
          payload.add(<String, Object?>{'type': 'text', 'text': text});
        case AiChatContentPartKind.imageFile:
          final filePath = (part.filePath ?? '').trim();
          final mimeType = (part.mimeType ?? '').trim();
          if (filePath.isEmpty || mimeType.isEmpty) {
            continue;
          }
          payload.add(<String, Object?>{
            'type': 'image_url',
            'image_url': <String, Object?>{
              'url': await encodeFileAsDataUrl(
                filePath: filePath,
                mimeType: mimeType,
              ),
              'detail': 'auto',
            },
          });
      }
    }
    return payload;
  }

  /// Merges consecutive messages that share the `system` role into a single
  /// message by concatenating their `content` fields with double newlines.
  /// This ensures broad compatibility with OpenAI-compatible providers that
  /// only accept a single system message.
  static List<Map<String, Object?>> _mergeConsecutiveSystemMessages(
    List<Map<String, Object?>> messages,
  ) {
    if (messages.length <= 1) return messages;
    final result = <Map<String, Object?>>[];
    StringBuffer? pendingSystem;
    for (final msg in messages) {
      if (msg['role'] == 'system' && msg['content'] is String) {
        pendingSystem ??= StringBuffer();
        if (pendingSystem.isNotEmpty) pendingSystem.write('\n\n');
        pendingSystem.write(msg['content'] as String);
      } else {
        if (pendingSystem != null) {
          result.add(<String, Object?>{
            'role': 'system',
            'content': pendingSystem.toString(),
          });
          pendingSystem = null;
        }
        result.add(msg);
      }
    }
    if (pendingSystem != null) {
      result.add(<String, Object?>{
        'role': 'system',
        'content': pendingSystem.toString(),
      });
    }
    return result;
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
    return AiTokenUsageParser.parseOpenAi(usageMap);
  }

  @override
  Future<String> parseAssistantMessage(String rawResponse) async {
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

    // Try extracting from 'content' first.
    final content = message['content'];
    final contentText = await _extractOpenAiContentWithMediaSafe(content);
    if (contentText.isNotEmpty) {
      return contentText;
    }

    // Fallback: for reasoning models (e.g., deepseek-expert-reasoner),
    // check 'reasoning_content' if 'content' is empty. Some reasoning models
    // embed DSML tool calls in reasoning_content instead of using native
    // tool_calls — return reasoning_content to let the DSML parser extract them.
    final reasoningContent = message['reasoning_content'];
    if (reasoningContent != null) {
      final reasoningText = await _extractOpenAiContentWithMediaSafe(
        reasoningContent,
      );
      if (reasoningText.isNotEmpty) {
        return reasoningText;
      }
    }

    // If native tool_calls exist, it's valid to have empty text content.
    // Return empty string to allow tool call processing to proceed.
    final toolCalls = message['tool_calls'];
    if (toolCalls is List && toolCalls.isNotEmpty) {
      return '';
    }

    throw const FormatException('Empty assistant response text.');
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
          // Some OpenAI-compatible providers return `arguments` already as a
          // Map / List (rather than the spec's JSON-encoded string).  A bare
          // `'$value'` would yield Dart's `{key: value}` debug form, which
          // is not valid JSON and breaks downstream `_decodeToolArguments`.
          // Mirror the Claude/Gemini adapters and JSON-encode whenever we
          // get a structured value.
          final argsValue = functionMap['arguments'];
          final String arguments;
          if (argsValue is String) {
            arguments = argsValue;
          } else if (argsValue == null) {
            arguments = '';
          } else if (argsValue is Map || argsValue is List) {
            arguments = jsonEncode(argsValue);
          } else {
            arguments = '$argsValue';
          }
          return AiToolCall(
            id: id,
            name: name,
            arguments: arguments,
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
  bool get supportsServerStreaming => true;

  @override
  bool get supportsToolCalls => true;

  @override
  Map<String, String> buildHeaders(AiModelConfig model) {
    final headers = super.buildHeaders(model);
    headers.putIfAbsent('anthropic-version', () => '2023-06-01');
    return headers;
  }

  @override
  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    final systemContent = messages
        .where((item) => item.role == AiChatRole.system)
        .map((item) => item.content.trim())
        .where((item) => item.isNotEmpty)
        .join('\n\n');
    final nonSystemMessages = messages
        .where((item) => item.role != AiChatRole.system)
        .toList();
    final requestMessages = await _mapClaudeMessages(nonSystemMessages);
    final effectiveMaxTokens = model.maxTokens ?? 1024;
    final cacheEnabled = inputCacheConfig?.isEffectivelyEnabled ?? false;
    // Claude prompt caching: total cache_control markers <= 4 across system +
    // tools + messages, otherwise the API rejects with 400. We allocate the
    // user-configured budget greedily across (system end, tools end, static
    // message prefix end, sliding tail per mode/interval).
    int remainingBreakpoints = cacheEnabled
        ? inputCacheConfig!.breakpointCount.clamp(1, 4)
        : 0;

    Object? systemPayload;
    if (systemContent.isNotEmpty) {
      if (cacheEnabled && remainingBreakpoints > 0) {
        systemPayload = <Map<String, Object?>>[
          <String, Object?>{
            'type': 'text',
            'text': systemContent,
            'cache_control': <String, Object?>{'type': 'ephemeral'},
          },
        ];
        remainingBreakpoints -= 1;
      } else {
        systemPayload = systemContent;
      }
    }

    Object? toolsPayload;
    if (tools.isNotEmpty) {
      final toolJson = tools
          .map((item) => item.toClaudeJson())
          .toList(growable: false);
      if (cacheEnabled && remainingBreakpoints > 0 && toolJson.isNotEmpty) {
        // Anthropic accepts cache_control on the last tool definition; this
        // freezes the entire tool block.
        final mutableTools = toolJson
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList(growable: false);
        mutableTools.last['cache_control'] = <String, Object?>{
          'type': 'ephemeral',
        };
        toolsPayload = mutableTools;
        remainingBreakpoints -= 1;
      } else {
        toolsPayload = toolJson;
      }
    }

    if (cacheEnabled && remainingBreakpoints > 0 && requestMessages.isNotEmpty) {
      _injectMessageCacheBreakpoints(
        requestMessages,
        budget: remainingBreakpoints,
        config: inputCacheConfig!,
      );
    }

    return <String, Object?>{
      'model': model.modelId,
      if (systemPayload != null) 'system': systemPayload,
      'max_tokens': effectiveMaxTokens,
      if (model.temperature != null) 'temperature': model.temperature,
      if (stream) 'stream': true,
      if (toolsPayload != null) 'tools': toolsPayload,
      if (tools.isNotEmpty) 'tool_choice': <String, Object?>{'type': 'auto'},
      'messages': requestMessages,
    };
  }

  /// 在 [requestMessages] 上按 mode/interval 注入剩余 cache_control breakpoint。
  /// 命中点位于命中消息的最后一个 content 块上。
  void _injectMessageCacheBreakpoints(
    List<Map<String, Object?>> requestMessages,
    {required int budget, required AiInputCacheRuntimeConfig config}) {
    if (budget <= 0 || requestMessages.isEmpty) return;
    // 2026-05-04 — 优先尊重用户自定义的前 N-1 个静态缓存点位置。
    // 当 positions 长度匹配 (breakpointCount-1) 时：
    //   * 前 N-1 个断点 = positions[i] * (msgs.length-1) round 后的索引；
    //   * 最后一个断点 = msgs.length-1 (固定落在尾部)；
    //   * 索引去重，再按预算 budget 截断。
    final positions = config.breakpointPositions;
    final lastIndex = requestMessages.length - 1;
    if (positions.isNotEmpty && positions.length == config.breakpointCount - 1) {
      final selected = <int>{lastIndex};
      for (final p in positions) {
        final clamped = p.isFinite ? p.clamp(0.0, 1.0) : 1.0;
        final idx = (clamped * lastIndex).round().clamp(0, lastIndex);
        selected.add(idx);
      }
      final ordered = selected.toList()..sort((a, b) => b.compareTo(a));
      for (final index in ordered.take(budget)) {
        _attachCacheControlToMessageTail(requestMessages[index]);
      }
      return;
    }
    // 候选索引从尾部回溯，按 mode 过滤；保证最少打到最后一条消息。
    final candidates = <int>[];
    final interval = config.updateInterval <= 0 ? 1 : config.updateInterval;
    switch (config.mode) {
      case 'userMessages':
        var seenUsers = 0;
        for (var i = requestMessages.length - 1; i >= 0; i--) {
          if (requestMessages[i]['role'] == 'user') {
            if (seenUsers % interval == 0) candidates.add(i);
            seenUsers++;
          }
        }
        break;
      case 'tokens':
        // 粗略以累计 char 长度模拟 token 累计，跨过 interval 即落点。
        var charAcc = 0;
        for (var i = requestMessages.length - 1; i >= 0; i--) {
          charAcc += _estimateMessageChars(requestMessages[i]);
          if (charAcc >= interval || i == requestMessages.length - 1) {
            candidates.add(i);
            charAcc = 0;
          }
        }
        break;
      case 'allMessages':
      default:
        for (var i = requestMessages.length - 1; i >= 0; i -= interval) {
          candidates.add(i);
        }
        break;
    }
    final selected = candidates.take(budget).toList(growable: false);
    for (final index in selected) {
      _attachCacheControlToMessageTail(requestMessages[index]);
    }
  }

  int _estimateMessageChars(Map<String, Object?> message) {
    final content = message['content'];
    if (content is String) return content.length;
    if (content is List) {
      var total = 0;
      for (final block in content) {
        if (block is Map) {
          final t = block['text'];
          if (t is String) total += t.length;
          final c = block['content'];
          if (c is String) total += c.length;
        }
      }
      return total;
    }
    return 0;
  }

  void _attachCacheControlToMessageTail(Map<String, Object?> message) {
    final content = message['content'];
    if (content is String) {
      message['content'] = <Map<String, Object?>>[
        <String, Object?>{
          'type': 'text',
          'text': content,
          'cache_control': <String, Object?>{'type': 'ephemeral'},
        },
      ];
      return;
    }
    if (content is List<Map<String, Object?>>) {
      if (content.isEmpty) return;
      content.last['cache_control'] = <String, Object?>{'type': 'ephemeral'};
      return;
    }
    if (content is List) {
      // List<dynamic>; mutate the last entry if it's a Map.
      if (content.isEmpty) return;
      final last = content.last;
      if (last is Map<String, Object?>) {
        last['cache_control'] = <String, Object?>{'type': 'ephemeral'};
      } else if (last is Map) {
        final m = Map<String, Object?>.from(last);
        m['cache_control'] = <String, Object?>{'type': 'ephemeral'};
        content[content.length - 1] = m;
      }
    }
  }

  @override
  bool supportsAttachmentsForModel(AiModelConfig model) {
    final profileOverride = model.profileFor(model.modelId).isMultimodal;
    if (profileOverride != null) return profileOverride;
    return _containsAny(model.modelId, const <String>[
      'claude-3',
      'claude-4',
      'claude-sonnet',
      'claude-opus',
      'claude-haiku',
    ]);
  }

  /// Maps a sequence of [AiChatTurn] messages into Claude API format,
  /// handling tool_use (assistant) and tool_result (user) content blocks.
  ///
  /// Claude requires:
  /// - Assistant messages that invoked tools include `tool_use` content blocks.
  /// - Tool results are sent as `user` messages with `tool_result` blocks.
  /// - Consecutive messages with the same role are merged (Claude rejects
  ///   adjacent same-role messages).
  Future<List<Map<String, Object?>>> _mapClaudeMessages(
    List<AiChatTurn> turns,
  ) async {
    final result = <Map<String, Object?>>[];

    for (final turn in turns) {
      if (turn.role == AiChatRole.assistant && turn.toolCalls.isNotEmpty) {
        // Assistant message that made tool calls — emit content blocks.
        final contentBlocks = <Map<String, Object?>>[];
        final text = turn.content.trim();
        if (text.isNotEmpty) {
          contentBlocks.add(<String, Object?>{'type': 'text', 'text': text});
        }
        for (final tc in turn.toolCalls) {
          Object? parsedArgs;
          try {
            parsedArgs = jsonDecode(tc.arguments);
          } catch (_) {
            parsedArgs = <String, Object?>{};
          }
          contentBlocks.add(<String, Object?>{
            'type': 'tool_use',
            'id': tc.id,
            'name': tc.name,
            'input': parsedArgs,
          });
        }
        result.add(<String, Object?>{
          'role': 'assistant',
          'content': contentBlocks,
        });
      } else if (turn.role == AiChatRole.tool) {
        // Tool result — Claude expects this as a user message with
        // tool_result content block.
        final toolResultBlock = <String, Object?>{
          'type': 'tool_result',
          'tool_use_id': turn.toolCallId ?? '',
          'content': turn.content,
        };
        // Merge with previous user message if possible to avoid
        // consecutive user messages.
        if (result.isNotEmpty && result.last['role'] == 'user') {
          final prevContent = result.last['content'];
          if (prevContent is List<Map<String, Object?>>) {
            prevContent.add(toolResultBlock);
          } else if (prevContent is String && prevContent.isNotEmpty) {
            // Preserve existing text content when merging tool results.
            result.last['content'] = <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': prevContent},
              toolResultBlock,
            ];
          } else {
            result.last['content'] = <Map<String, Object?>>[toolResultBlock];
          }
        } else {
          result.add(<String, Object?>{
            'role': 'user',
            'content': <Map<String, Object?>>[toolResultBlock],
          });
        }
      } else {
        // Regular user/assistant text message.
        final mapped = await _mapClaudeMessage(turn);
        result.add(mapped);
      }
    }

    return result;
  }

  Future<Map<String, Object?>> _mapClaudeMessage(AiChatTurn item) async {
    final contentParts = item.effectiveParts;
    if (contentParts.isEmpty ||
        contentParts.every((part) => part.kind == AiChatContentPartKind.text)) {
      final textContent = contentParts.isEmpty
          ? item.content
          : contentParts.map((part) => part.text ?? '').join('\n\n').trim();
      return <String, Object?>{
        'role': item.role == AiChatRole.user ? 'user' : 'assistant',
        'content': textContent,
      };
    }
    return <String, Object?>{
      'role': item.role == AiChatRole.user ? 'user' : 'assistant',
      'content': await _mapClaudeContentParts(contentParts),
    };
  }

  Future<List<Map<String, Object?>>> _mapClaudeContentParts(
    List<AiChatContentPart> parts,
  ) async {
    final payload = <Map<String, Object?>>[];
    for (final part in parts) {
      switch (part.kind) {
        case AiChatContentPartKind.text:
          final text = (part.text ?? '').trim();
          if (text.isEmpty) {
            continue;
          }
          payload.add(<String, Object?>{'type': 'text', 'text': text});
        case AiChatContentPartKind.imageFile:
          final filePath = (part.filePath ?? '').trim();
          final mimeType = (part.mimeType ?? '').trim();
          if (filePath.isEmpty || mimeType.isEmpty) {
            continue;
          }
          final bytes = await File(filePath).readAsBytes();
          payload.add(<String, Object?>{
            'type': 'image',
            'source': <String, Object?>{
              'type': 'base64',
              'media_type': mimeType,
              'data': base64Encode(bytes),
            },
          });
      }
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
    final parsed = AiTokenUsageParser.parseClaude(usageMap);
    if (parsed != null && kDebugMode) {
      // 2026-05-04 — 缓存命中诊断：观察 cache_read 与 cache_creation 比例。
      // 期望第二轮起 cache_read >> cache_creation。若每轮都偏向 creation，
      // 说明前缀有漂移源（settings 改动 / catalog 重排 / 时间戳渗透）。
      debugPrint(
        '[claude.cache] read=${parsed.cacheReadTokens} '
        'creation=${parsed.cacheCreationTokens} '
        'input=${parsed.promptTokens} output=${parsed.completionTokens}',
      );
    }
    return parsed;
  }

  @override
  Future<String> parseAssistantMessage(String rawResponse) async {
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
      final type = '${item['type'] ?? ''}'.trim();
      // Text block.
      if (type == 'text' || type.isEmpty) {
        final text = '${item['text'] ?? ''}'.trim();
        if (text.isEmpty) continue;
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(text);
        continue;
      }
      // Image block (Claude may return base64 images in the future).
      if (type == 'image') {
        final source = item['source'];
        if (source is Map<String, Object?>) {
          final sourceType = '${source['type'] ?? ''}'.trim();
          final mediaType = '${source['media_type'] ?? ''}'.trim();
          final data = '${source['data'] ?? ''}'.trim();
          if (sourceType == 'base64' &&
              mediaType.isNotEmpty &&
              data.isNotEmpty) {
            final md = await saveInlineMediaToMarkdown(
              AiInlineMedia(mimeType: mediaType, base64Data: data),
            );
            if (md.isNotEmpty) {
              if (buffer.isNotEmpty) buffer.writeln();
              buffer.writeln();
              buffer.write(md);
            }
          }
        }
        continue;
      }
    }
    final output = buffer.toString().trim();
    if (output.isEmpty) {
      // When Claude returns only tool_use blocks with no text, return empty
      // string rather than throwing — the tool calls carry the response.
      return '';
    }
    return output;
  }

  @override
  List<AiToolCall> parseToolCalls(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return const <AiToolCall>[];
    }
    final content = decoded['content'];
    if (content is! List) {
      return const <AiToolCall>[];
    }
    final calls = <AiToolCall>[];
    for (final item in content) {
      if (item is! Map<String, Object?>) continue;
      final type = '${item['type'] ?? ''}'.trim();
      if (type != 'tool_use') continue;
      final id = '${item['id'] ?? ''}'.trim();
      final name = '${item['name'] ?? ''}'.trim();
      if (id.isEmpty || name.isEmpty) continue;
      final input = item['input'];
      final arguments = input is Map ? jsonEncode(input) : '{}';
      calls.add(AiToolCall(id: id, name: name, arguments: arguments));
    }
    return calls;
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
  bool get supportsServerStreaming => true;

  @override
  bool get supportsToolCalls => true;

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
  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    final systemContent = messages
        .where((item) => item.role == AiChatRole.system)
        .map((item) => item.content.trim())
        .where((item) => item.isNotEmpty)
        .join('\n\n');
    final nonSystemMessages = messages
        .where((item) => item.role != AiChatRole.system)
        .toList();
    final requestContents = await _mapGeminiMessages(nonSystemMessages);

    /// Determine effective response modalities:
    /// 1. If the caller explicitly requests modalities (e.g. from creation mode),
    ///    use those directly.
    /// 2. Otherwise, detect from the model name (image-capable models).
    final effectiveModalities = responseModalities.isNotEmpty
        ? responseModalities
        : model.modelId.toLowerCase().contains('image')
        ? const <String>['Text', 'Image']
        : const <String>[];

    return <String, Object?>{
      if (systemContent.isNotEmpty)
        'systemInstruction': <String, Object?>{
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': systemContent},
          ],
        },
      'contents': requestContents,
      'generationConfig': <String, Object?>{
        'maxOutputTokens': model.maxTokens ?? 8192,
        if (model.temperature != null) 'temperature': model.temperature,
        if (effectiveModalities.isNotEmpty)
          'responseModalities': effectiveModalities,
      },
      if (tools.isNotEmpty)
        'tools': <Map<String, Object?>>[
          <String, Object?>{
            'functionDeclarations': tools
                .map(
                  (item) => <String, Object?>{
                    'name': item.name,
                    'description': item.description,
                    'parameters': item.parameters,
                  },
                )
                .toList(growable: false),
          },
        ],
    };
  }

  @override
  bool supportsAttachmentsForModel(AiModelConfig model) {
    final profileOverride = model.profileFor(model.modelId).isMultimodal;
    if (profileOverride != null) return profileOverride;
    return _containsAny(model.modelId, const <String>[
      'gemini-1.5',
      'gemini-2.0',
      'gemini-2.5',
      'gemini',
    ]);
  }

  /// Maps a sequence of [AiChatTurn] into Gemini API format, handling
  /// tool calls (functionCall parts) and tool results (functionResponse parts).
  ///
  /// Gemini requires:
  /// - Model messages with `functionCall` parts for tool invocations.
  /// - User messages with `functionResponse` parts for tool results.
  Future<List<Map<String, Object?>>> _mapGeminiMessages(
    List<AiChatTurn> turns,
  ) async {
    final result = <Map<String, Object?>>[];
    // Track tool call ID → function name for resolving functionResponse.
    final toolCallIdToName = <String, String>{};

    for (final turn in turns) {
      if (turn.role == AiChatRole.assistant && turn.toolCalls.isNotEmpty) {
        // Model message with function calls.
        final parts = <Map<String, Object?>>[];
        final text = turn.content.trim();
        if (text.isNotEmpty) {
          parts.add(<String, Object?>{'text': text});
        }
        for (final tc in turn.toolCalls) {
          toolCallIdToName[tc.id] = tc.name;
          Object? parsedArgs;
          try {
            parsedArgs = jsonDecode(tc.arguments);
          } catch (_) {
            parsedArgs = <String, Object?>{};
          }
          parts.add(<String, Object?>{
            'functionCall': <String, Object?>{
              'name': tc.name,
              'args': parsedArgs,
            },
          });
        }
        result.add(<String, Object?>{'role': 'model', 'parts': parts});
      } else if (turn.role == AiChatRole.tool) {
        // Tool result → functionResponse part.
        // Gemini requires the function name, not the call ID.
        final callId = turn.toolCallId ?? '';
        final functionName = toolCallIdToName[callId] ?? callId;
        Object? parsedContent;
        try {
          parsedContent = jsonDecode(turn.content);
        } catch (_) {
          parsedContent = <String, Object?>{'result': turn.content};
        }
        final responseBlock = <String, Object?>{
          'functionResponse': <String, Object?>{
            'name': functionName,
            'response': parsedContent,
          },
        };
        // Merge with previous user message if possible.
        if (result.isNotEmpty && result.last['role'] == 'user') {
          final prevParts = result.last['parts'];
          if (prevParts is List<Map<String, Object?>>) {
            prevParts.add(responseBlock);
          } else {
            result.last['parts'] = <Map<String, Object?>>[responseBlock];
          }
        } else {
          result.add(<String, Object?>{
            'role': 'user',
            'parts': <Map<String, Object?>>[responseBlock],
          });
        }
      } else {
        result.add(await _mapGeminiMessage(turn));
      }
    }

    return result;
  }

  Future<Map<String, Object?>> _mapGeminiMessage(AiChatTurn item) async {
    final parts = await _mapGeminiContentParts(item.effectiveParts);
    // Gemini API rejects messages with an empty parts array.
    if (parts.isEmpty) {
      parts.add(<String, Object?>{'text': ' '});
    }
    return <String, Object?>{
      'role': item.role == AiChatRole.assistant ? 'model' : 'user',
      'parts': parts,
    };
  }

  Future<List<Map<String, Object?>>> _mapGeminiContentParts(
    List<AiChatContentPart> parts,
  ) async {
    final payload = <Map<String, Object?>>[];
    for (final part in parts) {
      switch (part.kind) {
        case AiChatContentPartKind.text:
          final text = (part.text ?? '').trim();
          if (text.isEmpty) {
            continue;
          }
          payload.add(<String, Object?>{'text': text});
        case AiChatContentPartKind.imageFile:
          final filePath = (part.filePath ?? '').trim();
          final mimeType = (part.mimeType ?? '').trim();
          if (filePath.isEmpty || mimeType.isEmpty) {
            continue;
          }
          final bytes = await File(filePath).readAsBytes();
          payload.add(<String, Object?>{
            'inline_data': <String, Object?>{
              'mime_type': mimeType,
              'data': base64Encode(bytes),
            },
          });
      }
    }
    return payload;
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
    return AiTokenUsageParser.parseGemini(usageMap);
  }

  @override
  Future<String> parseAssistantMessage(String rawResponse) async {
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
      // Text part.
      final text = '${item['text'] ?? ''}'.trim();
      if (text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(text);
        continue;
      }
      // Inline media part (image, audio, video).
      final inlineData = item['inline_data'] ?? item['inlineData'];
      if (inlineData is Map<String, Object?>) {
        final mimeType =
            '${inlineData['mime_type'] ?? inlineData['mimeType'] ?? ''}'.trim();
        final data = '${inlineData['data'] ?? ''}'.trim();
        if (mimeType.isNotEmpty && data.isNotEmpty) {
          final md = await saveInlineMediaToMarkdown(
            AiInlineMedia(mimeType: mimeType, base64Data: data),
          );
          if (md.isNotEmpty) {
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.writeln();
            buffer.write(md);
          }
        }
        continue;
      }
      // File data part (Gemini API can return file URIs).
      final fileData = item['file_data'] ?? item['fileData'];
      if (fileData is Map<String, Object?>) {
        final mimeType =
            '${fileData['mime_type'] ?? fileData['mimeType'] ?? ''}'.trim();
        final fileUri = '${fileData['file_uri'] ?? fileData['fileUri'] ?? ''}'
            .trim();
        if (fileUri.isNotEmpty) {
          final label = mimeType.startsWith('image/')
              ? 'AI Generated Image'
              : mimeType.startsWith('video/')
              ? 'AI Generated Video'
              : mimeType.startsWith('audio/')
              ? 'AI Generated Audio'
              : 'AI Generated File';
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.writeln();
          if (mimeType.startsWith('image/')) {
            buffer.write('![$label]($fileUri)');
          } else if (mimeType.startsWith('video/') ||
              mimeType.startsWith('audio/')) {
            buffer.write('[$label]($fileUri)');
          } else {
            buffer.write('[$label]($fileUri)');
          }
        }
        continue;
      }
    }
    final output = buffer.toString().trim();
    if (output.isEmpty) {
      // When Gemini returns only function call parts with no text, return
      // empty string — the tool calls carry the response.
      return '';
    }
    return output;
  }

  @override
  List<AiToolCall> parseToolCalls(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map<String, Object?>) {
      return const <AiToolCall>[];
    }
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return const <AiToolCall>[];
    }
    final firstCandidate = candidates.first;
    if (firstCandidate is! Map<String, Object?>) {
      return const <AiToolCall>[];
    }
    final content = firstCandidate['content'];
    if (content is! Map<String, Object?>) {
      return const <AiToolCall>[];
    }
    final parts = content['parts'];
    if (parts is! List) {
      return const <AiToolCall>[];
    }
    final calls = <AiToolCall>[];
    var index = 0;
    for (final part in parts) {
      if (part is! Map<String, Object?>) continue;
      final functionCall = part['functionCall'];
      if (functionCall is! Map<String, Object?>) continue;
      final name = '${functionCall['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final args = functionCall['args'];
      final arguments = args is Map ? jsonEncode(args) : '{}';
      calls.add(
        AiToolCall(id: 'gemini-tc-$index', name: name, arguments: arguments),
      );
      index++;
    }
    return calls;
  }
}

/// Adapter for Ollama's OpenAI-compatible endpoint.
///
/// Ollama exposes `/v1/chat/completions` but has several behavioural
/// differences compared to the upstream OpenAI API:
///   * Authentication is typically unnecessary for local deployments.
///   * Older Ollama versions may ignore `stream_options`.
///   * The usage object in streaming responses may use
///     `eval_count` / `prompt_eval_count` instead of the standard
///     OpenAI field names.
///   * Multimodal support depends on the loaded model (e.g. llava,
///     llama3.2-vision, moondream).
class OllamaProtocolAdapter extends OpenAiProtocolAdapter {
  const OllamaProtocolAdapter({
    List<String> visionModelPatterns = const <String>[],
  }) : super(AiProtocolType.ollama, visionModelPatterns: visionModelPatterns);

  @override
  Map<String, String> buildHeaders(AiModelConfig model) {
    // Ollama is commonly deployed locally without authentication.
    // When the user has not set a token we can skip the auth header
    // entirely to avoid confusing the server with an empty value.
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

  @override
  Future<Map<String, Object?>> buildBody(
    AiModelConfig model,
    List<AiChatTurn> messages, {
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    bool stream = false,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    final body = await super.buildBody(
      model,
      messages,
      tools: tools,
      responseModalities: responseModalities,
      stream: stream,
      inputCacheConfig: inputCacheConfig,
    );
    // Older Ollama releases do not recognise `stream_options` and may
    // reject the request or ignore it silently.  Remove it to maximise
    // compatibility across versions.
    body.remove('stream_options');
    return body;
  }

  @override
  AiTokenUsage? parseUsage(String rawResponse) {
    // Try the standard OpenAI-compatible parser first (covers cached_tokens
    // when newer Ollama builds expose it via prompt_tokens_details).
    final standardUsage = super.parseUsage(rawResponse);
    if (standardUsage != null && !standardUsage.isEmpty) {
      return standardUsage;
    }
    // Fall back to Ollama-native field names that some versions emit.
    try {
      final decoded = jsonDecode(rawResponse);
      if (decoded is! Map<String, Object?>) return null;
      final promptEval = _readInt(decoded['prompt_eval_count']);
      final evalCount = _readInt(decoded['eval_count']);
      if (promptEval == null && evalCount == null) return null;
      return AiTokenUsage(
        promptTokens: promptEval,
        completionTokens: evalCount,
        totalTokens: (promptEval ?? 0) + (evalCount ?? 0),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String extractErrorMessage(String rawResponse) {
    // Ollama sometimes returns a plain-text error or an `{"error":"..."}` JSON.
    try {
      final decoded = jsonDecode(rawResponse);
      if (decoded is Map<String, Object?>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return error.trim();
        }
      }
    } catch (_) {
      // Fall through – treat the whole body as a message.
    }
    return rawResponse.trim();
  }
}

abstract final class AiProtocolRegistry {
  // ─────────────────────────────────────────────────────────────────────────
  // Vision model detection patterns — per-provider.
  //
  // Each list contains case-insensitive substrings that, when found in a
  // model ID, indicate the model accepts inline image content parts.
  // Patterns are derived from each provider's official API documentation.
  // ─────────────────────────────────────────────────────────────────────────

  /// OpenAI: GPT-4o+, o-series, and common multimodal models served via
  /// OpenAI-compatible proxy endpoints (Claude, Gemini, open-source VLMs).
  static const _openaiVisionPatterns = <String>[
    // Native OpenAI vision models.
    'gpt-4o', 'gpt-4.1', 'gpt-4.5', 'gpt-5',
    'o1', 'o3', 'o4',
    'vision', 'omni',
    // Claude / Gemini models served through OpenAI-compatible proxies.
    'claude-3', 'claude-4', 'claude-sonnet', 'claude-opus', 'claude-haiku',
    'gemini',
    // Open-source VLMs commonly accessed via OpenAI-compatible APIs.
    'llava', 'pixtral', 'internvl', 'minicpm-v', 'cogvlm', 'moondream',
    'qwen-vl', 'qwen2-vl', 'qwen2.5-vl',
    'multimodal', 'multi-modal',
  ];

  /// DeepSeek: Only explicitly vision-capable model IDs.
  /// Note: deepseek-chat / deepseek-reasoner are text-only per official API.
  static const _deepseekVisionPatterns = <String>[
    'vision',
    'vl',
    'janus',
    'multimodal',
    'multi-modal',
  ];

  /// Qwen (DashScope): VL / Omni models via OpenAI-compatible endpoint.
  /// Note: qwen-plus / qwen-max / qwen-turbo without -vl are text-only.
  static const _qwenVisionPatterns = <String>['vl', 'omni', 'vision', 'doc'];

  /// Kimi (Moonshot): Vision and multimodal model IDs.
  static const _kimiVisionPatterns = <String>[
    'vision',
    'vl',
    'moonshot-v',
    'k1.5-vision',
    'k2-vision',
    'k2.5-vision',
  ];

  /// GLM (Zhipu BigModel): GLM-4V / GLM-4.5V vision models.
  static const _glmVisionPatterns = <String>[
    'glm-4v',
    'glm-4.5v',
    '4v',
    'vision',
    'vl',
    'vlm',
  ];

  /// Grok (xAI): Vision-capable Grok model IDs.
  static const _grokVisionPatterns = <String>[
    'vision',
    'grok-2-vision',
    'grok-vision',
  ];

  /// Ollama: Common local multimodal models.
  static const _ollamaVisionPatterns = <String>[
    'llava',
    'llama3.2-vision',
    'moondream',
    'bakllava',
    'minicpm-v',
    'cogvlm',
    'internvl',
    'vision',
  ];

  /// vLLM: Open-source VLMs served via vLLM.
  static const _vllmVisionPatterns = <String>[
    'llava',
    'pixtral',
    'internvl',
    'qwen-vl',
    'qwen2-vl',
    'qwen2.5-vl',
    'minicpm-v',
    'cogvlm',
    'vision',
  ];

  /// SGLang: Open-source VLMs served via SGLang.
  static const _sglangVisionPatterns = <String>[
    'llava',
    'pixtral',
    'internvl',
    'qwen-vl',
    'qwen2-vl',
    'qwen2.5-vl',
    'vision',
  ];

  /// Seed / Doubao (Volcengine): Vision models.
  /// Official API uses standard OpenAI image_url format.
  static const _seedVisionPatterns = <String>[
    'vision',
    'vl',
    'doubao-vision',
    'doubao-1.5-vision',
  ];

  /// StepFun: Step vision model IDs.
  static const _stepfunVisionPatterns = <String>[
    'step-2v',
    'step-1.5v',
    'step-1v',
    'vision',
    'vl',
  ];

  /// MIMO: Vision-capable model IDs.
  static const _mimoVisionPatterns = <String>['vision', 'vl'];

  /// MiniMax: M-series text models plus explicit vision/VL variants.
  static const _minimaxVisionPatterns = <String>['vision', 'vl', 'm2-vl'];

  /// LongCat / JoyCode are OpenAI-compatible providers; treat only explicit
  /// vision model IDs as attachment-capable.
  static const _longCatVisionPatterns = <String>['vision', 'vl'];
  static const _joyCodeVisionPatterns = <String>['vision', 'vl'];

  /// Baidu ERNIE / Wenxin: ERNIE-VL model families.
  static const _wenxinVisionPatterns = <String>[
    'ernie-vl',
    'ernie-4.5-vl',
    'vision',
    'vl',
  ];

  /// Meta AI / Llama: official multimodal Llama families.
  static const _metaVisionPatterns = <String>[
    'llama-4',
    'llama3.2-vision',
    'llama-3.2-vision',
    'vision',
    'vl',
  ];

  /// Hunyuan (Tencent): Vision models via OpenAI-compatible endpoint.
  /// Official API: api.hunyuan.cloud.tencent.com/v1 with image_url format.
  static const _hunyuanVisionPatterns = <String>[
    'hunyuan-vision',
    'hunyuan-turbos-vision',
    'vision',
    'vl',
  ];

  static final Map<AiProtocolType, AiProtocolAdapter> _adapters =
      <AiProtocolType, AiProtocolAdapter>{
        AiProtocolType.openai: const OpenAiProtocolAdapter(
          AiProtocolType.openai,
          visionModelPatterns: _openaiVisionPatterns,
        ),
        AiProtocolType.deepseek: const OpenAiProtocolAdapter(
          AiProtocolType.deepseek,
          visionModelPatterns: _deepseekVisionPatterns,
        ),
        AiProtocolType.qwen: const OpenAiProtocolAdapter(
          AiProtocolType.qwen,
          visionModelPatterns: _qwenVisionPatterns,
        ),
        AiProtocolType.kimi: const OpenAiProtocolAdapter(
          AiProtocolType.kimi,
          visionModelPatterns: _kimiVisionPatterns,
        ),
        AiProtocolType.glm: const OpenAiProtocolAdapter(
          AiProtocolType.glm,
          visionModelPatterns: _glmVisionPatterns,
        ),
        AiProtocolType.grok: const OpenAiProtocolAdapter(
          AiProtocolType.grok,
          visionModelPatterns: _grokVisionPatterns,
        ),
        AiProtocolType.ollama: const OllamaProtocolAdapter(
          visionModelPatterns: _ollamaVisionPatterns,
        ),
        AiProtocolType.vllm: const OpenAiProtocolAdapter(
          AiProtocolType.vllm,
          visionModelPatterns: _vllmVisionPatterns,
        ),
        AiProtocolType.sglang: const OpenAiProtocolAdapter(
          AiProtocolType.sglang,
          visionModelPatterns: _sglangVisionPatterns,
        ),
        AiProtocolType.seed: const OpenAiProtocolAdapter(
          AiProtocolType.seed,
          visionModelPatterns: _seedVisionPatterns,
        ),
        AiProtocolType.stepfun: const OpenAiProtocolAdapter(
          AiProtocolType.stepfun,
          visionModelPatterns: _stepfunVisionPatterns,
        ),
        AiProtocolType.minimax: const OpenAiProtocolAdapter(
          AiProtocolType.minimax,
          visionModelPatterns: _minimaxVisionPatterns,
        ),
        AiProtocolType.longcat: const OpenAiProtocolAdapter(
          AiProtocolType.longcat,
          visionModelPatterns: _longCatVisionPatterns,
        ),
        AiProtocolType.joycode: const OpenAiProtocolAdapter(
          AiProtocolType.joycode,
          visionModelPatterns: _joyCodeVisionPatterns,
        ),
        AiProtocolType.wenxin: const OpenAiProtocolAdapter(
          AiProtocolType.wenxin,
          visionModelPatterns: _wenxinVisionPatterns,
        ),
        AiProtocolType.meta: const OpenAiProtocolAdapter(
          AiProtocolType.meta,
          visionModelPatterns: _metaVisionPatterns,
        ),
        AiProtocolType.mimo: const OpenAiProtocolAdapter(
          AiProtocolType.mimo,
          visionModelPatterns: _mimoVisionPatterns,
        ),
        AiProtocolType.hunyuan: const OpenAiProtocolAdapter(
          AiProtocolType.hunyuan,
          visionModelPatterns: _hunyuanVisionPatterns,
        ),
        AiProtocolType.claude: const ClaudeProtocolAdapter(),
        AiProtocolType.gemini: const GeminiProtocolAdapter(),
      };

  static AiProtocolAdapter adapterFor(AiProtocolType protocolType) {
    return _adapters[protocolType] ?? _adapters[AiProtocolType.openai]!;
  }

  /// Returns `true` when [model] is expected to accept inline image content
  /// parts (e.g. base64-encoded images in the message body).
  static bool supportsInlineImages(AiModelConfig model) {
    return adapterFor(model.protocolType).supportsAttachmentsForModel(model);
  }
}

/// Extracts text and non-text content parts (images, audio) from OpenAI-compatible
/// (images, audio) that some OpenAI-compatible APIs return in assistants.
/// Returns empty string instead of throwing if content is empty/null.
Future<String> _extractOpenAiContentWithMediaSafe(Object? rawContent) async {
  try {
    return await _extractOpenAiContentWithMedia(rawContent);
  } on FormatException {
    return '';
  }
}

/// Extracts text and non-text content parts (images, audio) from OpenAI-compatible
/// (images, audio) that some OpenAI-compatible APIs return in assistants.
Future<String> _extractOpenAiContentWithMedia(Object? rawContent) async {
  if (rawContent is String && rawContent.trim().isNotEmpty) {
    return rawContent.trim();
  }
  if (rawContent is List<dynamic>) {
    final buffer = StringBuffer();
    for (final item in rawContent) {
      if (item is String && item.trim().isNotEmpty) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(item.trim());
        continue;
      }
      if (item is! Map<String, Object?>) continue;
      final type = '${item['type'] ?? ''}'.trim();
      // Text block.
      if (type == 'text' || type.isEmpty) {
        final text = '${item['text'] ?? item['content'] ?? ''}'.trim();
        if (text.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.write(text);
        }
        continue;
      }
      // Image URL block (base64 data URI or remote URL).
      if (type == 'image_url') {
        final imageUrl = item['image_url'];
        if (imageUrl is Map<String, Object?>) {
          final url = '${imageUrl['url'] ?? ''}'.trim();
          if (url.startsWith('data:')) {
            // data:image/png;base64,...
            final commaIndex = url.indexOf(',');
            if (commaIndex > 0) {
              final header = url.substring(0, commaIndex);
              final mimeMatch = RegExp(r'data:([^;]+)').firstMatch(header);
              final mimeType = mimeMatch?.group(1) ?? 'image/png';
              final base64Data = url.substring(commaIndex + 1);
              final md = await saveInlineMediaToMarkdown(
                AiInlineMedia(mimeType: mimeType, base64Data: base64Data),
              );
              if (md.isNotEmpty) {
                if (buffer.isNotEmpty) buffer.writeln();
                buffer.writeln();
                buffer.write(md);
              }
            }
          } else if (url.isNotEmpty) {
            // Remote URL — render directly as markdown image.
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.writeln();
            buffer.write('![AI Generated Image]($url)');
          }
        }
        continue;
      }
      // Video block (some OpenAI-compatible providers return generated clips
      // in chat-style content arrays).
      if (type == 'video' || type == 'video_url') {
        final videoPayload = item['video'] ?? item['video_url'];
        final md = await _markdownFromOpenAiMediaPayload(
          videoPayload,
          fallbackMimeType: 'video/mp4',
          fallbackLabel: 'AI Generated Video',
        );
        if (md.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.writeln();
          buffer.write(md);
        }
        continue;
      }
      // Audio block (OpenAI gpt-4o-audio responses).
      if (type == 'audio') {
        final audioData = item['audio'];
        if (audioData is Map<String, Object?>) {
          final data = '${audioData['data'] ?? ''}'.trim();
          if (data.isNotEmpty) {
            final md = await saveInlineMediaToMarkdown(
              AiInlineMedia(mimeType: 'audio/mp3', base64Data: data),
              label: '${audioData['transcript'] ?? 'AI Audio Response'}',
            );
            if (md.isNotEmpty) {
              if (buffer.isNotEmpty) buffer.writeln();
              buffer.writeln();
              buffer.write(md);
            }
          }
          final url = '${audioData['url'] ?? audioData['audio_url'] ?? ''}'
              .trim();
          if (url.isNotEmpty) {
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.writeln();
            buffer.write('[AI Audio Response]($url)');
          }
          // Include transcript as text if present.
          final transcript = '${audioData['transcript'] ?? ''}'.trim();
          if (transcript.isNotEmpty) {
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.write(transcript);
          }
        }
        continue;
      }
    }
    final output = buffer.toString().trim();
    if (output.isNotEmpty) {
      return output;
    }
  }
  throw const FormatException('Empty assistant response text.');
}

Future<String> _markdownFromOpenAiMediaPayload(
  Object? payload, {
  required String fallbackMimeType,
  required String fallbackLabel,
}) async {
  if (payload is String) {
    final trimmed = payload.trim();
    if (trimmed.startsWith('data:')) {
      final commaIndex = trimmed.indexOf(',');
      if (commaIndex > 0) {
        final header = trimmed.substring(0, commaIndex);
        final mimeMatch = RegExp(r'data:([^;]+)').firstMatch(header);
        final mimeType = mimeMatch?.group(1) ?? fallbackMimeType;
        final base64Data = trimmed.substring(commaIndex + 1);
        return saveInlineMediaToMarkdown(
          AiInlineMedia(mimeType: mimeType, base64Data: base64Data),
          label: fallbackLabel,
        );
      }
    }
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('file:')) {
      return '[$fallbackLabel]($trimmed)';
    }
    return '';
  }
  if (payload is! Map<String, Object?>) return '';
  final data = '${payload['data'] ?? payload['base64'] ?? ''}'.trim();
  final mimeType =
      '${payload['mime_type'] ?? payload['mimeType'] ?? fallbackMimeType}'
          .trim();
  final label = '${payload['transcript'] ?? payload['title'] ?? fallbackLabel}'
      .trim();
  if (data.isNotEmpty) {
    return saveInlineMediaToMarkdown(
      AiInlineMedia(
        mimeType: mimeType.isEmpty ? fallbackMimeType : mimeType,
        base64Data: data,
      ),
      label: label.isEmpty ? fallbackLabel : label,
    );
  }
  final url =
      '${payload['url'] ?? payload['video_url'] ?? payload['audio_url'] ?? ''}'
          .trim();
  if (url.isNotEmpty) {
    return '[${sanitizeMarkdownAltText(label.isEmpty ? fallbackLabel : label)}]($url)';
  }
  return '';
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

bool _containsAny(String value, List<String> candidates) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  for (final candidate in candidates) {
    if (normalized.contains(candidate.toLowerCase())) {
      return true;
    }
  }
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline media extraction helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Decoded inline media block from an AI response.
class AiInlineMedia {
  const AiInlineMedia({required this.mimeType, required this.base64Data});

  final String mimeType;
  final String base64Data;

  /// Returns a short human-readable media type label.
  String get mediaKind {
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.startsWith('audio/')) return 'audio';
    if (mimeType.startsWith('video/')) return 'video';
    return 'file';
  }

  /// File extension inferred from the MIME type.
  String get fileExtension {
    return switch (mimeType) {
      'image/png' => '.png',
      'image/jpeg' || 'image/jpg' => '.jpg',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'image/svg+xml' => '.svg',
      'audio/mp3' || 'audio/mpeg' => '.mp3',
      'audio/wav' || 'audio/x-wav' => '.wav',
      'audio/ogg' => '.ogg',
      'audio/aac' => '.aac',
      'video/mp4' => '.mp4',
      'video/webm' => '.webm',
      _ => '',
    };
  }
}

/// Shared directory for inline media artifacts. Using one directory (instead
/// of a fresh `createTemp` per call) means stale files can be pruned as a
/// batch and we don't leak one directory per rendered media asset.
Directory? _inlineMediaDir;
Future<Directory> _ensureInlineMediaDir() async {
  final existing = _inlineMediaDir;
  if (existing != null && await existing.exists()) return existing;
  final dir = Directory(p.join(Directory.systemTemp.path, 'openhand_media'));
  await dir.create(recursive: true);
  _inlineMediaDir = dir;
  return dir;
}

/// Best-effort removal of inline media files older than 7 days. Safe to call
/// repeatedly and never throws.
Future<void> pruneInlineMediaCache() async {
  try {
    final dir = Directory(p.join(Directory.systemTemp.path, 'openhand_media'));
    if (!await dir.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } on FileSystemException {
        // Skip files we cannot stat or delete.
      }
    }
  } on FileSystemException {
    // Swallow — cleanup failures are never fatal.
  }
}

/// Saves an [AiInlineMedia] to a temp file and returns a markdown reference.
///
/// Images are rendered as `![...](file_path)` so the markdown renderer can
/// display them inline. Audio/video use a link `[🔊 ...](file_path)`.
Future<String> saveInlineMediaToMarkdown(
  AiInlineMedia media, {
  String? label,
}) async {
  try {
    final bytes = base64Decode(media.base64Data);
    if (bytes.isEmpty) return '';
    final tempDir = await _ensureInlineMediaDir();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final fileName = '${media.mediaKind}_$id${media.fileExtension}';
    final file = File(p.join(tempDir.path, fileName));
    await file.writeAsBytes(bytes);
    final filePath = file.path;
    final displayLabel = sanitizeMarkdownAltText(
      label ?? 'AI Generated ${media.mediaKind}',
    );
    if (media.mimeType.startsWith('image/')) {
      return '![$displayLabel]($filePath)';
    }
    if (media.mimeType.startsWith('audio/')) {
      return '[🔊 $displayLabel]($filePath)';
    }
    if (media.mimeType.startsWith('video/')) {
      return '[🎬 $displayLabel]($filePath)';
    }
    return '[📎 $displayLabel]($filePath)';
  } catch (e) {
    assert(() {
      // ignore: avoid_print
      print('[saveInlineMediaToMarkdown] Failed to persist media: $e');
      return true;
    }());
    return '';
  }
}

/// Sanitize a label for use as markdown image/link alt text.
///
/// Strips characters that break `![alt](url)` parsing: `[`, `]`, newlines.
/// Truncates to a reasonable length since the full user prompt can be very
/// long and makes no sense as alt text.
String sanitizeMarkdownAltText(String text) {
  var sanitized = text
      .replaceAll('[', '')
      .replaceAll(']', '')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ')
      .trim();
  if (sanitized.length > 120) {
    sanitized = '${sanitized.substring(0, 117)}...';
  }
  return sanitized;
}
