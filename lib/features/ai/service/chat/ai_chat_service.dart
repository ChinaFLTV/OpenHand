import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/ui/structured_error_text.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_dialect.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_creation_mode.dart';
import '../../model/ai_input_cache_runtime_config.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../dsml/ai_dsml_tool_call_parser.dart';
import '../media/ai_image_generation_service.dart';
import '../model_registry/ai_model_scanner.dart';
import '../operations/ai_responses_service.dart';
import '../session_io/ai_token_usage_parser.dart';
import 'ai_protocol_adapter.dart';
import 'ai_sse_data_parser.dart';
import 'ai_transport_diagnostic_messages.dart';

abstract class AiChatClient {
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools,
    List<String> responseModalities,
    AiCreationRequest creationRequest,
    Duration timeout,
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  });

  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools,
    List<String> responseModalities,
    AiCreationRequest creationRequest,
    Duration timeout,
    Duration streamIdleTimeout,
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  });

  Future<String> testModel(AiModelConfig model);

  void dispose();
}

class AiChatRequestTelemetry {
  const AiChatRequestTelemetry({
    this.requestUrl,
    this.requestMethod,
    this.requestHeaders,
    this.requestBody,
    this.rawResponse,
    this.startedAt,
    this.endedAt,
    this.durationMs,
    this.finishReason,
    this.error,
  });

  final String? requestUrl;
  final String? requestMethod;
  final Map<String, String>? requestHeaders;
  final Map<String, Object?>? requestBody;
  final String? rawResponse;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationMs;
  final String? finishReason;
  final String? error;
}

class AiChatCompletion {
  const AiChatCompletion({
    required this.reply,
    this.reasoningContent,
    this.usage,
    this.rawResponse,
    this.toolCalls = const <AiToolCall>[],
    this.requestUrl,
    this.requestMethod,
    this.requestHeaders,
    this.requestBody,
    this.startedAt,
    this.endedAt,
    this.durationMs,
  });

  final String reply;

  /// Reasoning / thinking content from models that support extended thinking
  /// (e.g., deepseek-expert-reasoner). Null when not available.
  final String? reasoningContent;

  final AiTokenUsage? usage;
  final String? rawResponse;
  final List<AiToolCall> toolCalls;
  final String? requestUrl;
  final String? requestMethod;
  final Map<String, String>? requestHeaders;
  final Map<String, Object?>? requestBody;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationMs;
}

enum AiChatStreamEventType { textDelta, reasoningDelta, toolCallDelta, usage }

class AiToolCallDelta {
  const AiToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsFragment = '',
  });

  final int index;
  final String? id;
  final String? name;
  final String argumentsFragment;
}

class AiChatStreamEvent {
  const AiChatStreamEvent._({
    required this.type,
    this.textDelta,
    this.reasoningDelta,
    this.toolCallDelta,
    this.usage,
  });

  const AiChatStreamEvent.textDelta(String value)
    : this._(type: AiChatStreamEventType.textDelta, textDelta: value);

  const AiChatStreamEvent.reasoningDelta(String value)
    : this._(type: AiChatStreamEventType.reasoningDelta, reasoningDelta: value);

  const AiChatStreamEvent.toolCallDelta(AiToolCallDelta value)
    : this._(type: AiChatStreamEventType.toolCallDelta, toolCallDelta: value);

  const AiChatStreamEvent.usage(AiTokenUsage value)
    : this._(type: AiChatStreamEventType.usage, usage: value);

  final AiChatStreamEventType type;
  final String? textDelta;
  final String? reasoningDelta;
  final AiToolCallDelta? toolCallDelta;
  final AiTokenUsage? usage;
}

class AiChatStreamResult {
  const AiChatStreamResult({
    required this.reply,
    required this.reasoning,
    required this.toolCalls,
    this.wasCancelled = false,
    this.usage,
    this.rawResponse,
    this.finishReason,
    this.requestUrl,
    this.requestMethod,
    this.requestHeaders,
    this.requestBody,
    this.startedAt,
    this.endedAt,
    this.durationMs,
  });

  final String reply;
  final String reasoning;
  final List<AiToolCall> toolCalls;
  final bool wasCancelled;
  final AiTokenUsage? usage;
  final String? rawResponse;
  final String? requestUrl;
  final String? requestMethod;
  final Map<String, String>? requestHeaders;
  final Map<String, Object?>? requestBody;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationMs;

  /// The reason the model stopped generating.
  ///
  /// Common values:
  ///   - `'stop'` / `'end_turn'` — normal completion
  ///   - `'length'` / `'max_tokens'` — output truncated due to token limit
  ///   - `'tool_calls'` / `'tool_use'` — model requested tool execution
  ///   - `null` — unknown or not reported
  final String? finishReason;

  /// Whether the model output was truncated due to reaching the max output
  /// token limit.  This is a common cause of "silent stops" where the model
  /// appears to have finished but actually ran out of output budget.
  bool get wasTruncated {
    final normalized = optionalLowercaseStringFromValue(finishReason);
    return normalized == 'length' || normalized == 'max_tokens';
  }
}

class AiChatStreamingResponse {
  const AiChatStreamingResponse({
    required this.events,
    required this.result,
    this.cancel,
  });

  final Stream<AiChatStreamEvent> events;
  final Future<AiChatStreamResult> result;
  final Future<void> Function()? cancel;
}

class AiChatService implements AiChatClient {
  AiChatService({
    http.Client? client,
    AiImageGenerationService? imageService,
    AiModelScanner? modelScanner,
  }) : _client = client ?? SystemProxyResolver.instance.createHttpClient(),
       _imageService = imageService ?? AiImageGenerationService(client: client),
       _modelScanner = modelScanner;

  static const String _availabilityProbePrompt =
      'Reply with OK only if this model configuration works.';

  /// Defensive cap for the SSE line buffer. A well-behaved server delimits
  /// events with `\n\n`, keeping per-block size in the KB range. If a buggy
  /// or hostile server streams megabytes without a delimiter we discard the
  /// pending buffer instead of letting it grow without bound and OOM the
  /// process. 4 MiB is far above any realistic single-event size while
  /// remaining cheap to retain.
  int maxStreamLineBufferBytes = 4 * kBytesPerMiB;

  final http.Client _client;
  final AiImageGenerationService _imageService;
  final AiModelScanner? _modelScanner;
  AiResponsesService? _responsesService;

  /// Returns true when [creationRequest] asks for media output and the
  /// selected model exposes the matching generation capability. Gemini keeps
  /// its inline `responseModalities` path on the chat endpoint, so it is not
  /// diverted here.
  ///
  /// We trust the model-level capability resolver because it already prefers
  /// explicit profile flags and the curated catalog before falling back to
  /// the per-protocol matrix. This keeps user-configured media-only models
  /// (e.g. `grok-imagine-video`, custom DashScope `wan` aliases) from being
  /// silently routed to `/v1/chat/completions` and hitting HTTP 405.
  bool _shouldDivertToMediaEndpoint(
    AiModelConfig model,
    AiCreationRequest creationRequest,
  ) {
    return switch (creationRequest.mode) {
      AiCreationMode.image =>
        AiImageGenerationService.supportsImageGenerationForModel(model),
      AiCreationMode.video =>
        AiImageGenerationService.supportsVideoGenerationForModel(model),
      AiCreationMode.audio =>
        AiImageGenerationService.supportsAudioGenerationForModel(model),
      AiCreationMode.none || AiCreationMode.deepResearch => false,
    };
  }

  bool _canUseResponsesFamily({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    required List<AiToolDefinition> tools,
    required List<String> responseModalities,
    required AiCreationRequest creationRequest,
  }) {
    if (model.apiDialect != AiApiDialect.openAiCompat ||
        creationRequest.mode != AiCreationMode.none ||
        tools.isNotEmpty ||
        responseModalities.isNotEmpty) {
      return false;
    }
    if (!_hasExplicitResponsesCapability(model)) {
      return false;
    }
    return messages.every(
      (item) =>
          item.effectiveParts.isEmpty ||
          item.effectiveParts.every(
            (part) => part.kind == AiChatContentPartKind.text,
          ),
    );
  }

  bool _hasExplicitResponsesCapability(AiModelConfig model) {
    if (model.providerKind == AiProviderKind.openai) {
      return true;
    }
    if (model.endpointOverrides.containsKey(AiApiFamily.responses)) {
      return true;
    }
    final responsesModelId = model.operationRouting.responsesModelId;
    return nullIfBlank(responsesModelId) != null;
  }

  String _effectiveRequestMethod(AiModelConfig model) {
    return nullIfBlank(model.requestMethod) ?? 'POST';
  }

  bool _shouldFallbackFromResponsesStream(AiChatException error) {
    final requestUrl = error.telemetry?.requestUrl?.toLowerCase() ?? '';
    if (!requestUrl.contains('/responses')) {
      return false;
    }
    final message = error.message.toLowerCase();
    return message.contains('404') || message.contains('405');
  }

  bool _shouldRetryWithoutCacheAffinity({
    required int statusCode,
    required String errorBody,
    required Map<String, Object?> requestBody,
    required Map<String, String> requestHeaders,
  }) {
    if (statusCode < 400 || statusCode >= 500) {
      return false;
    }
    if (!AiPromptCacheAffinity.requestHasMarker(
      body: requestBody,
      headers: requestHeaders,
    )) {
      return false;
    }
    final normalized = errorBody.toLowerCase();
    final mentionsAffinityField =
        normalized.contains(
          AiPromptCacheAffinity.openAiPromptCacheKeyBodyField,
        ) ||
        normalized.contains(AiPromptCacheAffinity.openRouterSessionBodyField) ||
        normalized.contains(AiPromptCacheAffinity.openRouterSessionHeader) ||
        normalized.contains(AiPromptCacheAffinity.grokConversationHeader);
    if (mentionsAffinityField) {
      return normalized.contains('unknown') ||
          normalized.contains('unrecognized') ||
          normalized.contains('unsupported') ||
          normalized.contains('unexpected') ||
          normalized.contains('not allowed') ||
          normalized.contains('additional') ||
          normalized.contains('invalid');
    }
    if (statusCode != 400 && statusCode != 422) {
      return false;
    }
    return normalized.contains('invalid') ||
        normalized.contains('schema') ||
        normalized.contains('parameter') ||
        normalized.contains('field') ||
        normalized.contains('body') ||
        normalized.contains('request') ||
        normalized.contains('bad request') ||
        normalized.contains('unrecognized') ||
        normalized.contains('unsupported') ||
        normalized.contains('unexpected') ||
        normalized.contains('additional');
  }

  AiRequestBlueprint _withoutCacheAffinityMarkers(
    AiRequestBlueprint blueprint,
  ) {
    return AiRequestBlueprint(
      url: blueprint.url,
      headers: AiPromptCacheAffinity.withoutHeaderMarkers(blueprint.headers),
      body: AiPromptCacheAffinity.withoutBodyMarkers(blueprint.body),
    );
  }

  /// Throws an [AiChatException] with a user-friendly message when the caller
  /// asks for video/audio output but the active model has no generation
  /// capability. Without this guard the request would fall through to the
  /// chat completions endpoint and surface as a confusing HTTP 405/404.
  void _assertCreationModeIsRoutable(
    AiModelConfig model,
    AiCreationRequest creationRequest,
  ) {
    switch (creationRequest.mode) {
      case AiCreationMode.video:
        if (!AiImageGenerationService.supportsVideoGenerationForModel(model)) {
          throw AiChatException(
            '当前模型 "${model.modelId}" 不具备视频生成能力，请切换到具备视频生成能力的模型后再试。',
          );
        }
        break;
      case AiCreationMode.audio:
        if (!AiImageGenerationService.supportsAudioGenerationForModel(model)) {
          throw AiChatException(
            '当前模型 "${model.modelId}" 不具备音频生成能力，请切换到具备音频生成能力的模型后再试。',
          );
        }
        break;
      case AiCreationMode.image:
      case AiCreationMode.none:
      case AiCreationMode.deepResearch:
        break;
    }
  }

  /// Extracts the latest user text prompt from a turn list. The image
  /// endpoints want a single clean prompt, not a chat history.
  ///
  /// The prompt builder prepends structured headers like
  /// `# [6] Your latest message\n\n` to the user content for the chat
  /// endpoint. These must be stripped before forwarding to the image API.
  static final RegExp _structuredPromptHeaderPattern = RegExp(
    r'^#\s*\[\d+\]\s*[^\n]*\n+',
  );

  String _latestUserPromptFromTurns(List<AiChatTurn> messages) {
    for (final turn in messages.reversed) {
      if (turn.role != AiChatRole.user) continue;
      final raw = turn.content.trim();
      if (raw.isNotEmpty) {
        return raw.replaceFirst(_structuredPromptHeaderPattern, '').trim();
      }
      final parts = trimmedNonEmptyStrings(
        turn.effectiveParts
            .where((p) => p.kind == AiChatContentPartKind.text)
            .map((p) => p.text),
      ).join('\n');
      if (parts.isNotEmpty) {
        return parts.replaceFirst(_structuredPromptHeaderPattern, '').trim();
      }
    }
    return '';
  }

  List<AiChatContentPart> _latestUserImagePartsFromTurns(
    List<AiChatTurn> messages,
  ) {
    for (final turn in messages.reversed) {
      if (turn.role != AiChatRole.user) continue;
      final imageParts = turn.effectiveParts
          .where((part) => part.kind == AiChatContentPartKind.imageFile)
          .toList(growable: false);
      if (imageParts.isNotEmpty) return imageParts;
    }
    return const <AiChatContentPart>[];
  }

  /// Produces an [AiChatCompletion] by calling a dedicated media generation
  /// endpoint and wrapping its output in the regular chat completion shape so
  /// the rest of the app can stay oblivious.
  Future<AiChatCompletion> _sendMediaGenerationCompletion({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    required AiCreationRequest creationRequest,
    required Duration timeout,
  }) async {
    final prompt = _latestUserPromptFromTurns(messages);
    final referenceImages = _latestUserImagePartsFromTurns(messages);
    final result = switch (creationRequest.mode) {
      AiCreationMode.image => await _imageService.generateImage(
        model: model,
        prompt: prompt,
        options: creationRequest.options,
        referenceImages: referenceImages,
        timeout: timeout,
      ),
      AiCreationMode.video => await _imageService.generateVideo(
        model: model,
        prompt: prompt,
        options: creationRequest.options,
        referenceImages: referenceImages,
        timeout: timeout,
      ),
      AiCreationMode.audio => await _imageService.generateAudio(
        model: model,
        prompt: prompt,
        options: creationRequest.options,
        timeout: timeout,
      ),
      AiCreationMode.none ||
      AiCreationMode.deepResearch => throw const AiMediaGenerationException(
        'No media generation mode was requested.',
      ),
    };
    return AiChatCompletion(
      reply: result.markdown,
      rawResponse: result.rawResponseBody,
      requestUrl: result.requestUrl,
      requestMethod: 'POST',
      requestHeaders: result.requestHeaders,
      requestBody: result.requestBody,
      startedAt: result.startedAt,
      endedAt: result.endedAt,
      durationMs: result.durationMs,
      usage: result.usage,
    );
  }

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 60),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) async {
    _assertCreationModeIsRoutable(model, creationRequest);
    if (_shouldDivertToMediaEndpoint(model, creationRequest)) {
      try {
        return await _awaitWithCancelSignal(
          _sendMediaGenerationCompletion(
            model: model,
            messages: messages,
            creationRequest: creationRequest,
            timeout: timeout,
          ),
          cancelSignal,
        );
      } on AiMediaGenerationException catch (error) {
        throw AiChatException(error.message);
      }
    }
    final canUseResponses = _canUseResponsesFamily(
      model: model,
      messages: messages,
      tools: tools,
      responseModalities: responseModalities,
      creationRequest: creationRequest,
    );
    if (canUseResponses) {
      final flattenedInput = trimmedNonEmptyStrings(
        messages.map((item) => '${item.roleName}: ${item.content}'),
      ).join('\n\n');
      try {
        _responsesService ??= AiResponsesService();
        final response = await _awaitWithCancelSignal(
          _responsesService!.createResponse(
            model: model,
            input: flattenedInput,
            timeout: timeout,
          ),
          cancelSignal,
        );
        return AiChatCompletion(
          reply: response.text,
          reasoningContent: response.reasoning,
          rawResponse: response.rawResponse,
        );
      } on AiChatCancelledException {
        rethrow;
      } catch (_) {
        // Fall back to the existing chat/completions path when the provider
        // does not actually expose a compatible /responses family yet.
      }
    }
    try {
      final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
      var blueprint = await adapter.buildChatRequest(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        inputCacheConfig: inputCacheConfig,
      );
      final effectiveMethod = _effectiveRequestMethod(model);
      final startedAt = DateTime.now().toUtc();
      AiChatRequestTelemetry telemetry({
        String? rawResponse,
        DateTime? endedAt,
        String? error,
      }) {
        final resolvedEndedAt = endedAt ?? DateTime.now().toUtc();
        return AiChatRequestTelemetry(
          requestUrl: blueprint.url,
          requestMethod: effectiveMethod,
          requestHeaders: Map<String, String>.unmodifiable(blueprint.headers),
          requestBody: blueprint.body,
          rawResponse: rawResponse,
          startedAt: startedAt,
          endedAt: resolvedEndedAt,
          durationMs: resolvedEndedAt.difference(startedAt).inMilliseconds,
          error: error,
        );
      }

      Future<http.Response> sendBlueprint(AiRequestBlueprint next) async {
        blueprint = next;
        onRequestStarted?.call(
          AiChatRequestTelemetry(
            requestUrl: blueprint.url,
            requestMethod: effectiveMethod,
            requestHeaders: Map<String, String>.unmodifiable(blueprint.headers),
            requestBody: blueprint.body,
            startedAt: startedAt,
          ),
        );
        try {
          return await _awaitWithCancelSignal(
            _sendHttpRequestWithRedirects(
              client: _client,
              method: effectiveMethod,
              uri: Uri.parse(blueprint.url),
              headers: blueprint.headers,
              body: jsonEncode(blueprint.body),
              timeout: timeout,
            ).then(http.Response.fromStream),
            cancelSignal,
          );
        } on AiChatCancelledException {
          rethrow;
        } on TimeoutException {
          final message = AiTransportDiagnosticMessages.timeout(timeout);
          throw AiChatException(message, telemetry: telemetry(error: message));
        } on HandshakeException catch (error) {
          final message = AiTransportDiagnosticMessages.handshake(error);
          throw AiChatException(message, telemetry: telemetry(error: message));
        } on TlsException catch (error) {
          final message = AiTransportDiagnosticMessages.tls(error);
          throw AiChatException(message, telemetry: telemetry(error: message));
        } on SocketException catch (error) {
          final message = AiTransportDiagnosticMessages.socket(error);
          throw AiChatException(message, telemetry: telemetry(error: message));
        } on http.ClientException catch (error) {
          final message = AiTransportDiagnosticMessages.httpClient(error);
          throw AiChatException(message, telemetry: telemetry(error: message));
        }
      }

      var response = await sendBlueprint(blueprint);
      var endedAt = DateTime.now().toUtc();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (_shouldRetryWithoutCacheAffinity(
          statusCode: response.statusCode,
          errorBody: response.body,
          requestBody: blueprint.body,
          requestHeaders: blueprint.headers,
        )) {
          response = await sendBlueprint(
            _withoutCacheAffinityMarkers(blueprint),
          );
          endedAt = DateTime.now().toUtc();
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorMessage = adapter.extractErrorMessage(response.body);
        final message = AiTransportDiagnosticMessages.httpStatus(
          response.statusCode,
          serverMessage: errorMessage,
        );
        throw AiChatException(
          message,
          telemetry: telemetry(
            rawResponse: response.body,
            endedAt: endedAt,
            error: message,
          ),
        );
      }
      try {
        final parsedReply = await adapter.parseAssistantMessage(response.body);
        final parsedToolCalls = adapter.parseToolCalls(response.body);
        final dsmlExtraction = extractDsmlToolCalls(parsedReply);
        // Extract reasoning_content separately (for reasoning models like
        // deepseek-expert-reasoner that return thinking in a dedicated field).
        final reasoningText = _extractReasoningContent(response.body);
        // When the model's `content` field is empty, parseAssistantMessage
        // falls back to `reasoning_content`, which means parsedReply IS the
        // reasoning text.  Deduplicate: keep reasoning separate and clear
        // the reply so the UI doesn't show the same text in both a thinking
        // card and an assistant card.
        final replyIsReasoning =
            reasoningText != null && nullIfBlank(parsedReply) == reasoningText;
        return AiChatCompletion(
          reply: replyIsReasoning ? '' : dsmlExtraction.sanitizedText,
          reasoningContent: reasoningText,
          usage: adapter.parseUsage(response.body),
          rawResponse: response.body,
          toolCalls: parsedToolCalls.isNotEmpty
              ? parsedToolCalls
              : dsmlExtraction.toolCalls,
          requestUrl: blueprint.url,
          requestMethod: effectiveMethod,
          requestHeaders: Map<String, String>.unmodifiable(blueprint.headers),
          requestBody: blueprint.body,
          startedAt: startedAt,
          endedAt: endedAt,
          durationMs: endedAt.difference(startedAt).inMilliseconds,
        );
      } on FormatException catch (error) {
        throw AiChatException(
          error.message,
          telemetry: telemetry(
            rawResponse: response.body,
            endedAt: endedAt,
            error: error.message,
          ),
        );
      }
    } on TimeoutException {
      throw AiChatException(AiTransportDiagnosticMessages.timeout(timeout));
    } on HandshakeException catch (error) {
      throw AiChatException(AiTransportDiagnosticMessages.handshake(error));
    } on TlsException catch (error) {
      throw AiChatException(AiTransportDiagnosticMessages.tls(error));
    } on SocketException catch (error) {
      throw AiChatException(AiTransportDiagnosticMessages.socket(error));
    } on http.ClientException catch (error) {
      throw AiChatException(AiTransportDiagnosticMessages.httpClient(error));
    }
  }

  /// Extracts `reasoning_content` from an OpenAI-compatible response body.
  /// Returns null if not present or empty.
  static String? _extractReasoningContent(String rawResponse) {
    try {
      final decoded = jsonDecode(rawResponse);
      if (decoded is! Map<String, Object?>) return null;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final message = (choices.first as Map<String, Object?>?)?['message'];
      if (message is! Map<String, Object?>) return null;
      final reasoning = message['reasoning_content'] ?? message['reasoning'];
      if (reasoning is String) return nullIfBlank(reasoning);
    } catch (error, stack) {
      silentLog('ai_chat_service', 'extract reasoning_content', error, stack);
    }
    return null;
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 60),
    Duration streamIdleTimeout = const Duration(seconds: 120),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) async {
    _assertCreationModeIsRoutable(model, creationRequest);
    final canUseResponses = _canUseResponsesFamily(
      model: model,
      messages: messages,
      tools: tools,
      responseModalities: responseModalities,
      creationRequest: creationRequest,
    );
    if (canUseResponses) {
      try {
        return await _sendResponsesStream(
          model: model,
          messages: messages,
          timeout: timeout,
          streamIdleTimeout: streamIdleTimeout,
          cancelSignal: cancelSignal,
          onRequestStarted: onRequestStarted,
        );
      } on AiChatException catch (error) {
        if (!_shouldFallbackFromResponsesStream(error)) {
          rethrow;
        }
      }
    }
    // Media generation is a one-shot or bounded-poll protocol on dedicated
    // endpoints, so wrap it in a synthetic stream that emits one textDelta
    // containing the final markdown media reference.
    if (_shouldDivertToMediaEndpoint(model, creationRequest)) {
      return _sendMessageAsSyntheticStream(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        creationRequest: creationRequest,
        timeout: timeout,
        cancelSignal: cancelSignal,
        onRequestStarted: onRequestStarted,
      );
    }
    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    if (!adapter.supportsServerStreaming) {
      return _sendMessageAsSyntheticStream(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        creationRequest: creationRequest,
        timeout: timeout,
        cancelSignal: cancelSignal,
        onRequestStarted: onRequestStarted,
      );
    }
    final isClaudeProtocol = adapter is ClaudeProtocolAdapter;
    final isGeminiProtocol = adapter is GeminiProtocolAdapter;

    var blueprint = await adapter.buildChatRequest(
      model: model,
      messages: messages,
      tools: tools,
      responseModalities: responseModalities,
      stream: true,
      inputCacheConfig: inputCacheConfig,
    );
    final effectiveMethod = _effectiveRequestMethod(model);
    late DateTime streamStartedAt;
    late Map<String, String> capturedHeaders;
    late Map<String, Object?> capturedBody;

    AiChatRequestTelemetry telemetrySnapshot({
      String? rawResponse,
      DateTime? endedAt,
      int? durationMs,
      String? finishReason,
      String? error,
    }) {
      final resolvedEndedAt = endedAt ?? DateTime.now().toUtc();
      return AiChatRequestTelemetry(
        requestUrl: blueprint.url,
        requestMethod: effectiveMethod,
        requestHeaders: capturedHeaders,
        requestBody: capturedBody,
        rawResponse: rawResponse,
        startedAt: streamStartedAt,
        endedAt: resolvedEndedAt,
        durationMs:
            durationMs ??
            resolvedEndedAt.difference(streamStartedAt).inMilliseconds,
        finishReason: finishReason,
        error: error,
      );
    }

    Future<http.StreamedResponse?> openStream(
      AiRequestBlueprint nextBlueprint,
    ) async {
      blueprint = nextBlueprint;
      streamStartedAt = DateTime.now().toUtc();
      capturedHeaders = Map<String, String>.unmodifiable(blueprint.headers);
      capturedBody = blueprint.body;
      onRequestStarted?.call(
        AiChatRequestTelemetry(
          requestUrl: blueprint.url,
          requestMethod: effectiveMethod,
          requestHeaders: capturedHeaders,
          requestBody: capturedBody,
          startedAt: streamStartedAt,
        ),
      );
      final request = http.Request(effectiveMethod, Uri.parse(blueprint.url))
        ..headers.addAll(blueprint.headers)
        ..body = jsonEncode(blueprint.body);
      final streamedResponseFuture = _sendHttpRequestWithRedirects(
        client: _client,
        method: request.method,
        uri: request.url,
        headers: request.headers,
        body: request.body,
        timeout: timeout,
      );
      try {
        if (cancelSignal == null) {
          return await streamedResponseFuture;
        }
        final firstResult = await Future.any<Object?>(<Future<Object?>>[
          streamedResponseFuture,
          cancelSignal.then((_) => _cancelledStreamSentinel),
        ]);
        if (!identical(firstResult, _cancelledStreamSentinel)) {
          return firstResult as http.StreamedResponse;
        }
        unawaited(
          streamedResponseFuture
              .then((response) => response.stream.drain<void>())
              .catchError((Object _, StackTrace stackTrace) {}),
        );
        return null;
      } on TimeoutException {
        final message = AiTransportDiagnosticMessages.timeout(timeout);
        throw AiChatException(
          message,
          telemetry: telemetrySnapshot(error: message),
        );
      } on HandshakeException catch (error) {
        final message = AiTransportDiagnosticMessages.handshake(error);
        throw AiChatException(
          message,
          telemetry: telemetrySnapshot(error: message),
        );
      } on TlsException catch (error) {
        final message = AiTransportDiagnosticMessages.tls(error);
        throw AiChatException(
          message,
          telemetry: telemetrySnapshot(error: message),
        );
      } on SocketException catch (error) {
        final message = AiTransportDiagnosticMessages.socket(error);
        throw AiChatException(
          message,
          telemetry: telemetrySnapshot(error: message),
        );
      } on http.ClientException catch (error) {
        final message = AiTransportDiagnosticMessages.httpClient(error);
        throw AiChatException(
          message,
          telemetry: telemetrySnapshot(error: message),
        );
      }
    }

    var streamedResponse = await openStream(blueprint);
    if (streamedResponse == null) {
      return AiChatStreamingResponse(
        events: const Stream<AiChatStreamEvent>.empty(),
        result: Future<AiChatStreamResult>.value(
          const AiChatStreamResult(
            reply: '',
            reasoning: '',
            toolCalls: <AiToolCall>[],
            wasCancelled: true,
          ),
        ),
      );
    }
    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      final initialErrorBody = await streamedResponse.stream.bytesToString();
      var finalErrorBody = initialErrorBody;
      if (_shouldRetryWithoutCacheAffinity(
        statusCode: streamedResponse.statusCode,
        errorBody: initialErrorBody,
        requestBody: blueprint.body,
        requestHeaders: blueprint.headers,
      )) {
        streamedResponse = await openStream(
          _withoutCacheAffinityMarkers(blueprint),
        );
        if (streamedResponse == null) {
          return AiChatStreamingResponse(
            events: const Stream<AiChatStreamEvent>.empty(),
            result: Future<AiChatStreamResult>.value(
              const AiChatStreamResult(
                reply: '',
                reasoning: '',
                toolCalls: <AiToolCall>[],
                wasCancelled: true,
              ),
            ),
          );
        }
        if (streamedResponse.statusCode < 200 ||
            streamedResponse.statusCode >= 300) {
          finalErrorBody = await streamedResponse.stream.bytesToString();
        }
      }
      if (streamedResponse.statusCode >= 200 &&
          streamedResponse.statusCode < 300) {
        // Retry succeeded; continue into the normal SSE reader below.
      } else {
        final errorMessage = adapter.extractErrorMessage(finalErrorBody);
        final message = AiTransportDiagnosticMessages.httpStatus(
          streamedResponse.statusCode,
          serverMessage: errorMessage,
        );
        throw AiChatException(
          message,
          telemetry: telemetrySnapshot(
            rawResponse: finalErrorBody,
            error: message,
          ),
        );
      }
    }
    final eventController = StreamController<AiChatStreamEvent>(sync: true);
    final resultCompleter = Completer<AiChatStreamResult>();
    final textBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final rawResponseBuffer = StringBuffer();
    final toolCalls = <int, _MutableToolCall>{};
    final emittedMediaUrls = <String>{};
    AiTokenUsage? usage;
    String? finishReason;
    final lineBuffer = StringBuffer();
    StreamSubscription<String>? responseSubscription;

    bool canEmitEvents() {
      return !resultCompleter.isCompleted && !eventController.isClosed;
    }

    void emitEvent(AiChatStreamEvent event) {
      if (!canEmitEvents()) {
        return;
      }
      eventController.add(event);
    }

    void emitGeneratedMediaIfPresent(Object? decoded) {
      final media = _extractStreamingGeneratedMedia(decoded);
      if (media == null || emittedMediaUrls.contains(media.url)) {
        return;
      }
      emittedMediaUrls.add(media.url);
      final markdown = media.toMarkdown();
      final prefix = textBuffer.isEmpty || textBuffer.toString().endsWith('\n')
          ? ''
          : '\n\n';
      final delta = '$prefix$markdown\n';
      textBuffer.write(delta);
      emitEvent(AiChatStreamEvent.textDelta(delta));
    }

    void completeStreamResult(String reason, {bool wasCancelled = false}) {
      if (resultCompleter.isCompleted) {
        return;
      }
      final resolvedToolCalls = toolCalls.entries.toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
      final streamedReply = textBuffer.toString().trim();
      final dsmlExtraction = extractDsmlToolCalls(streamedReply);
      final resolvedParsedToolCalls = resolvedToolCalls
          .map(
            (entry) => AiToolCall(
              id: entry.value.id.isEmpty
                  ? 'tool-call-${entry.key}'
                  : entry.value.id,
              name: entry.value.name,
              arguments: entry.value.argumentsBuffer.toString(),
            ),
          )
          .where((item) => nullIfBlank(item.name) != null)
          .toList(growable: false);
      // If the DSML parser detected incomplete markup AND finishReason was
      // not already set, infer truncation.  Some API providers (especially
      // third-party) may omit finish_reason, so the incomplete markup acts
      // as a reliable fallback signal.
      final effectiveFinishReason =
          dsmlExtraction.hasTrailingIncompleteMarkup && finishReason == null
          ? 'length'
          : finishReason;

      resultCompleter.complete(
        AiChatStreamResult(
          reply: dsmlExtraction.sanitizedText,
          reasoning: reasoningBuffer.toString().trim(),
          toolCalls: resolvedParsedToolCalls.isNotEmpty
              ? resolvedParsedToolCalls
              : dsmlExtraction.toolCalls,
          wasCancelled: wasCancelled,
          usage: usage,
          rawResponse: rawResponseBuffer.toString(),
          finishReason: effectiveFinishReason,
          requestUrl: blueprint.url,
          requestMethod: effectiveMethod,
          requestHeaders: capturedHeaders,
          requestBody: capturedBody,
          startedAt: streamStartedAt,
          endedAt: DateTime.now().toUtc(),
          durationMs: DateTime.now()
              .toUtc()
              .difference(streamStartedAt)
              .inMilliseconds,
        ),
      );
      if (!eventController.isClosed) {
        unawaited(eventController.close());
      }
    }

    void processEventBlock(String block) {
      if (resultCompleter.isCompleted) {
        return;
      }
      final dataLines = extractSseDataLines(block);
      if (dataLines.isEmpty) {
        return;
      }
      final data = dataLines.join('\n');
      if (data == '[DONE]') {
        completeStreamResult('done_marker');
        unawaited(responseSubscription?.cancel());
        return;
      }
      rawResponseBuffer.writeln(data);
      late final Object? decoded;
      try {
        decoded = jsonDecode(data);
      } catch (_) {
        emitGeneratedMediaIfPresent(data);
        return;
      }
      if (decoded is! Map<String, Object?>) {
        emitGeneratedMediaIfPresent(decoded);
        return;
      }

      // ── Detect in-stream error objects ──────────────────────────────────
      // Some API providers (especially third-party OpenAI-compatible ones)
      // return 200 OK but send error objects within the SSE data stream,
      // e.g. {"error": {"message": "Rate limit exceeded", ...}}.
      // Without this check, such errors are silently discarded and the
      // stream closes with an empty response.
      final errorField = decoded['error'];
      if (errorField != null) {
        String errorMessage;
        if (errorField is Map<String, Object?>) {
          errorMessage = '${errorField['message'] ?? errorField['msg'] ?? ''}'
              .trim();
          if (errorMessage.isEmpty) {
            errorMessage = '$errorField';
          }
        } else {
          errorMessage = '$errorField';
        }
        if (errorMessage.isNotEmpty) {
          if (!resultCompleter.isCompleted) {
            resultCompleter.completeError(
              AiChatException(
                'API error: $errorMessage',
                telemetry: telemetrySnapshot(
                  rawResponse: rawResponseBuffer.toString(),
                  finishReason: finishReason,
                  error: errorMessage,
                ),
              ),
              StackTrace.current,
            );
          }
          if (!eventController.isClosed) {
            unawaited(eventController.close());
          }
          unawaited(responseSubscription?.cancel());
          return;
        }
      }

      emitGeneratedMediaIfPresent(decoded);

      // Route to protocol-specific stream handler.
      if (isClaudeProtocol) {
        _processClaudeStreamEvent(
          decoded,
          textBuffer: textBuffer,
          reasoningBuffer: reasoningBuffer,
          toolCalls: toolCalls,
          usage: () => usage,
          setUsage: (value) => usage = value,
          emitEvent: emitEvent,
          completeStreamResult: (reason) => completeStreamResult(reason),
          cancelSubscription: () {
            unawaited(responseSubscription?.cancel());
          },
          setFinishReason: (value) => finishReason = value,
        );
      } else if (isGeminiProtocol) {
        _processGeminiStreamEvent(
          decoded,
          textBuffer: textBuffer,
          reasoningBuffer: reasoningBuffer,
          toolCalls: toolCalls,
          usage: () => usage,
          setUsage: (value) => usage = value,
          emitEvent: emitEvent,
          setFinishReason: (value) => finishReason = value,
        );
      } else {
        _processOpenAiStreamEvent(
          decoded,
          textBuffer: textBuffer,
          reasoningBuffer: reasoningBuffer,
          toolCalls: toolCalls,
          usage: () => usage,
          setUsage: (value) => usage = value,
          emitEvent: emitEvent,
          setFinishReason: (value) => finishReason = value,
        );
      }
    }

    void processChunk(String chunk) {
      lineBuffer.write(chunk.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
      // Defensive cap: if the buffer exceeds the threshold without a
      // `\n\n` delimiter, the upstream is misbehaving (or sending a single
      // event larger than any practical SSE payload). Drop the pending
      // bytes so we don't keep growing memory while the connection idles.
      if (lineBuffer.length > maxStreamLineBufferBytes) {
        lineBuffer.clear();
        return;
      }
      while (!resultCompleter.isCompleted) {
        // Avoid calling toString() on every iteration – check length first.
        if (lineBuffer.length < 2) {
          break;
        }
        final current = lineBuffer.toString();
        final separatorIndex = current.indexOf('\n\n');
        if (separatorIndex == -1) {
          break;
        }
        final block = current.substring(0, separatorIndex);
        final remaining = current.substring(separatorIndex + 2);
        lineBuffer
          ..clear()
          ..write(remaining);
        processEventBlock(block);
      }
    }

    responseSubscription = streamedResponse.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .timeout(streamIdleTimeout)
        .listen(
          processChunk,
          onError: (Object error, StackTrace stackTrace) {
            if (!resultCompleter.isCompleted) {
              final message = error is TimeoutException
                  ? AiTransportDiagnosticMessages.timeout(streamIdleTimeout)
                  : '$error';
              resultCompleter.completeError(
                AiChatException(
                  message,
                  telemetry: telemetrySnapshot(
                    rawResponse: rawResponseBuffer.toString(),
                    finishReason: finishReason,
                    error: message,
                  ),
                ),
                stackTrace,
              );
            }
            if (!eventController.isClosed) {
              unawaited(eventController.close());
            }
          },
          onDone: () {
            if (lineBuffer.isNotEmpty) {
              processEventBlock(lineBuffer.toString());
            }
            completeStreamResult('stream_closed');
          },
          cancelOnError: true,
        );

    return AiChatStreamingResponse(
      events: eventController.stream,
      result: resultCompleter.future,
      cancel: () async {
        completeStreamResult('cancelled', wasCancelled: true);
        await responseSubscription?.cancel();
      },
    );
  }

  Future<AiChatStreamingResponse> _sendResponsesStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    required Duration timeout,
    required Duration streamIdleTimeout,
    Future<void>? cancelSignal,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) async {
    _responsesService ??= AiResponsesService();
    final flattenedInput = trimmedNonEmptyStrings(
      messages.map((item) => '${item.roleName}: ${item.content}'),
    ).join('\n\n');
    final request = _responsesService!.buildRequest(
      model: model,
      input: flattenedInput,
      stream: true,
    );
    final streamStartedAt = DateTime.now().toUtc();
    final capturedHeaders = Map<String, String>.unmodifiable(request.headers);
    final capturedBody = request.body;
    onRequestStarted?.call(
      AiChatRequestTelemetry(
        requestUrl: request.url,
        requestMethod: request.method,
        requestHeaders: capturedHeaders,
        requestBody: capturedBody,
        startedAt: streamStartedAt,
      ),
    );
    final streamedResponseFuture = _sendHttpRequestWithRedirects(
      client: _client,
      method: request.method,
      uri: Uri.parse(request.url),
      headers: request.headers,
      body: jsonEncode(request.body),
      timeout: timeout,
    );
    late final http.StreamedResponse streamedResponse;
    if (cancelSignal == null) {
      streamedResponse = await streamedResponseFuture;
    } else {
      final firstResult = await Future.any(<Future<Object?>>[
        streamedResponseFuture,
        cancelSignal.then((_) => _cancelledStreamSentinel),
      ]);
      if (identical(firstResult, _cancelledStreamSentinel)) {
        return AiChatStreamingResponse(
          events: const Stream<AiChatStreamEvent>.empty(),
          result: Future<AiChatStreamResult>.value(
            const AiChatStreamResult(
              reply: '',
              reasoning: '',
              toolCalls: <AiToolCall>[],
              wasCancelled: true,
            ),
          ),
        );
      }
      streamedResponse = firstResult as http.StreamedResponse;
    }
    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      final errorBody = await streamedResponse.stream.bytesToString();
      throw AiChatException(
        AiTransportDiagnosticMessages.httpStatus(
          streamedResponse.statusCode,
          serverMessage: errorBody,
          contextHint: 'responses',
        ),
        telemetry: AiChatRequestTelemetry(
          requestUrl: request.url,
          requestMethod: request.method,
          requestHeaders: capturedHeaders,
          requestBody: capturedBody,
          rawResponse: errorBody,
          startedAt: streamStartedAt,
          endedAt: DateTime.now().toUtc(),
          durationMs: DateTime.now()
              .toUtc()
              .difference(streamStartedAt)
              .inMilliseconds,
          error: errorBody,
        ),
      );
    }

    final eventController = StreamController<AiChatStreamEvent>(sync: true);
    final resultCompleter = Completer<AiChatStreamResult>();
    final textBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final rawResponseBuffer = StringBuffer();
    final lineBuffer = StringBuffer();
    AiTokenUsage? usage;
    String? finishReason;

    void emitEvent(AiChatStreamEvent event) {
      if (!resultCompleter.isCompleted && !eventController.isClosed) {
        eventController.add(event);
      }
    }

    void processEventBlock(String block) {
      if (resultCompleter.isCompleted) return;
      final dataLines = extractSseDataLines(block);
      if (dataLines.isEmpty) return;
      final data = dataLines.join('\n');
      if (data == '[DONE]') {
        finishReason ??= 'stop';
        return;
      }
      rawResponseBuffer.writeln(data);
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, Object?>) return;
      _responsesService!.parseSseEvent(
        decoded,
        textBuffer: textBuffer,
        reasoningBuffer: reasoningBuffer,
        usage: () => usage,
        setUsage: (value) => usage = value,
        emitEvent: emitEvent,
        setFinishReason: (value) => finishReason = value,
      );
    }

    void processChunk(String chunk) {
      lineBuffer.write(chunk.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
      while (!resultCompleter.isCompleted) {
        if (lineBuffer.length < 2) break;
        final current = lineBuffer.toString();
        final separatorIndex = current.indexOf('\n\n');
        if (separatorIndex == -1) break;
        final block = current.substring(0, separatorIndex);
        final remaining = current.substring(separatorIndex + 2);
        lineBuffer
          ..clear()
          ..write(remaining);
        processEventBlock(block);
      }
    }

    late final StreamSubscription<String> responseSubscription;
    responseSubscription = streamedResponse.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .timeout(streamIdleTimeout)
        .listen(
          processChunk,
          onError: (Object error, StackTrace stackTrace) {
            if (!resultCompleter.isCompleted) {
              resultCompleter.completeError(error, stackTrace);
            }
            if (!eventController.isClosed) {
              unawaited(eventController.close());
            }
          },
          onDone: () {
            if (lineBuffer.isNotEmpty) {
              processEventBlock(lineBuffer.toString());
            }
            if (!resultCompleter.isCompleted) {
              resultCompleter.complete(
                AiChatStreamResult(
                  reply: textBuffer.toString().trim(),
                  reasoning: reasoningBuffer.toString().trim(),
                  toolCalls: const <AiToolCall>[],
                  usage: usage,
                  rawResponse: rawResponseBuffer.toString(),
                  finishReason: finishReason,
                  requestUrl: request.url,
                  requestMethod: request.method,
                  requestHeaders: capturedHeaders,
                  requestBody: capturedBody,
                  startedAt: streamStartedAt,
                  endedAt: DateTime.now().toUtc(),
                  durationMs: DateTime.now()
                      .toUtc()
                      .difference(streamStartedAt)
                      .inMilliseconds,
                ),
              );
            }
            if (!eventController.isClosed) {
              unawaited(eventController.close());
            }
          },
          cancelOnError: true,
        );

    return AiChatStreamingResponse(
      events: eventController.stream,
      result: resultCompleter.future,
      cancel: () async {
        await responseSubscription.cancel();
        if (!eventController.isClosed) {
          await eventController.close();
        }
      },
    );
  }

  Future<AiChatStreamingResponse> _sendMessageAsSyntheticStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    required List<AiToolDefinition> tools,
    required List<String> responseModalities,
    AiCreationRequest creationRequest = AiCreationRequest.none,
    required Duration timeout,
    Future<void>? cancelSignal,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) async {
    final controller = StreamController<AiChatStreamEvent>(sync: true);
    final completer = Completer<AiChatStreamResult>();
    // Internal cancel signal so `cancel()` can release the wrapper even
    // when the caller did not supply an external `cancelSignal`. The
    // underlying `sendMessage` HTTP cannot actually be aborted (the
    // `http.Client` API used here is non-cancellable), but at minimum
    // we stop *waiting* on it and surface a cancelled result immediately
    // so UI / controller code can move on.
    final internalCancelCompleter = Completer<void>();
    var cancelled = false;

    void completeCancelled() {
      if (cancelled) {
        return;
      }
      cancelled = true;
      if (!internalCancelCompleter.isCompleted) {
        internalCancelCompleter.complete();
      }
      if (!completer.isCompleted) {
        completer.complete(
          const AiChatStreamResult(
            reply: '',
            reasoning: '',
            toolCalls: <AiToolCall>[],
            wasCancelled: true,
          ),
        );
      }
    }

    unawaited(() async {
      try {
        final completionFuture = sendMessage(
          model: model,
          messages: messages,
          tools: tools,
          responseModalities: responseModalities,
          creationRequest: creationRequest,
          timeout: timeout,
          onRequestStarted: onRequestStarted,
        );
        // Race the actual completion against (a) the caller's cancel
        // signal, and (b) our internal signal raised by `cancel()`.
        // Either branch resolves immediately so the synthetic stream
        // wrapper can close even if the HTTP keeps running in the
        // background.
        final raceFutures = <Future<Object?>>[
          completionFuture,
          internalCancelCompleter.future.then((_) => _cancelledStreamSentinel),
          if (cancelSignal != null)
            cancelSignal.then((_) => _cancelledStreamSentinel),
        ];
        final completion = await Future.any(raceFutures).then((value) {
          if (identical(value, _cancelledStreamSentinel)) {
            completeCancelled();
            throw _SyntheticStreamCancelledException();
          }
          return value! as AiChatCompletion;
        });
        if (cancelled) {
          return;
        }
        if (completion.reply.isNotEmpty && !controller.isClosed) {
          controller.add(AiChatStreamEvent.textDelta(completion.reply));
        }
        if (completion.usage != null &&
            !completion.usage!.isEmpty &&
            !controller.isClosed) {
          controller.add(AiChatStreamEvent.usage(completion.usage!));
        }
        if (!completer.isCompleted) {
          completer.complete(
            AiChatStreamResult(
              reply: completion.reply,
              reasoning: '',
              toolCalls: completion.toolCalls,
              usage: completion.usage,
              rawResponse: completion.rawResponse,
              requestUrl: completion.requestUrl,
              requestMethod: completion.requestMethod,
              requestHeaders: completion.requestHeaders,
              requestBody: completion.requestBody,
              startedAt: completion.startedAt,
              endedAt: completion.endedAt,
              durationMs: completion.durationMs,
            ),
          );
        }
      } catch (error, stackTrace) {
        if (error is _SyntheticStreamCancelledException) {
          return;
        }
        if (!cancelled && !completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        await controller.close();
      }
    }());
    return AiChatStreamingResponse(
      events: controller.stream,
      result: completer.future,
      cancel: () async {
        completeCancelled();
        if (!controller.isClosed) {
          await controller.close();
        }
      },
    );
  }

  Future<T> _awaitWithCancelSignal<T>(
    Future<T> future,
    Future<void>? cancelSignal,
  ) async {
    if (cancelSignal == null) {
      return future;
    }
    final firstResult = await Future.any<Object?>(<Future<Object?>>[
      future.then<Object?>((value) => value),
      cancelSignal.then<Object?>((_) => _cancelledRequestSentinel),
    ]);
    if (identical(firstResult, _cancelledRequestSentinel)) {
      unawaited(
        future.then<void>(
          (value) {},
          onError: (Object error, StackTrace stackTrace) {},
        ),
      );
      throw const AiChatCancelledException();
    }
    return firstResult as T;
  }

  @override
  Future<String> testModel(AiModelConfig model) async {
    if (model.normalizedBaseUrl.isEmpty) {
      throw const AiChatException('Missing base URL.');
    }
    final modelId = nullIfBlank(model.modelId);
    if (modelId == null) {
      throw const AiChatException('Missing model ID.');
    }
    final probeModel = model.copyWith(
      clearMaxTokens: true,
      clearTemperature: true,
    );
    try {
      final reply = await sendMessage(
        model: probeModel,
        messages: const <AiChatTurn>[
          AiChatTurn(role: AiChatRole.user, content: _availabilityProbePrompt),
        ],
        timeout: const Duration(seconds: 20),
      );
      final normalizedReply = nullIfBlank(reply.reply);
      if (normalizedReply == null) {
        throw AiChatException(
          'Empty assistant reply.',
          telemetry: reply.requestUrl == null && reply.requestMethod == null
              ? null
              : AiChatRequestTelemetry(
                  requestUrl: reply.requestUrl,
                  requestMethod: reply.requestMethod,
                  requestHeaders: reply.requestHeaders,
                  requestBody: reply.requestBody,
                  rawResponse: reply.rawResponse,
                  startedAt: reply.startedAt,
                  endedAt: reply.endedAt,
                  durationMs: reply.durationMs,
                  error: 'Empty assistant reply.',
                ),
        );
      }
      return normalizedReply;
    } on AiChatException catch (error) {
      if (!_isOpenAiCompatibleProtocol(probeModel.protocolType)) {
        rethrow;
      }
      throw await _decorateProviderProbeFailure(
        probeModel,
        error,
        timeout: const Duration(seconds: 12),
      );
    }
  }

  @override
  void dispose() {
    _imageService.dispose();
    _client.close();
  }
}

const Object _cancelledRequestSentinel = Object();
const Object _cancelledStreamSentinel = Object();

class _SyntheticStreamCancelledException implements Exception {}

/// Processes a single SSE event block in OpenAI-compatible format.
void _processOpenAiStreamEvent(
  Map<String, Object?> decoded, {
  required StringBuffer textBuffer,
  required StringBuffer reasoningBuffer,
  required Map<int, _MutableToolCall> toolCalls,
  required AiTokenUsage? Function() usage,
  required void Function(AiTokenUsage?) setUsage,
  required void Function(AiChatStreamEvent) emitEvent,
  required void Function(String) setFinishReason,
}) {
  final usageJson = decoded['usage'];
  if (usageJson is Map || usageJson is Map<String, Object?>) {
    final usageMap = usageJson is Map<String, Object?>
        ? usageJson
        : stringKeyedMapFromValue(usageJson);
    final parsedUsage = AiTokenUsageParser.parseOpenAi(usageMap);
    if (parsedUsage != null && !parsedUsage.isEmpty) {
      // Merge with the previous frame so cache_* fields surfaced in an
      // earlier chunk are preserved when later chunks omit them. DeepSeek
      // and a few self-hosted gateways emit the cache stats only in the
      // very first/last chunk.
      final merged = AiTokenUsageParser.carryForward(usage(), parsedUsage);
      setUsage(merged);
      emitEvent(AiChatStreamEvent.usage(merged));
    }
  }
  final choices = decoded['choices'];
  if (choices is! List<dynamic>) {
    return;
  }
  for (final choice in choices) {
    if (choice is! Map<String, Object?>) {
      continue;
    }
    // Capture finish_reason from the final chunk – this tells us whether the
    // model stopped normally ("stop"), was truncated ("length"), or wants
    // tool execution ("tool_calls").
    final choiceFinishReason = optionalStringFromValue(choice['finish_reason']);
    if (choiceFinishReason != null) {
      setFinishReason(choiceFinishReason);
    }
    final delta = choice['delta'];
    if (delta is! Map<String, Object?>) {
      continue;
    }
    final textDelta = _extractStreamText(delta['content']);
    if (textDelta.isNotEmpty) {
      textBuffer.write(textDelta);
      emitEvent(AiChatStreamEvent.textDelta(textDelta));
    }
    final reasoningDelta = _extractReasoningText(delta);
    if (reasoningDelta.isNotEmpty) {
      reasoningBuffer.write(reasoningDelta);
      emitEvent(AiChatStreamEvent.reasoningDelta(reasoningDelta));
    }
    final toolCallJson = delta['tool_calls'];
    if (toolCallJson is! List) {
      continue;
    }
    for (final rawToolCall in toolCallJson) {
      if (rawToolCall is! Map) {
        continue;
      }
      final toolCallMap = stringKeyedMapFromValue(rawToolCall);
      // OpenAI streaming spec assigns each tool_call a stable `index`.
      // Some non-strict OpenAI-compatible providers omit it and instead
      // ship two complete tool_calls in a single chunk — both would then
      // bucket into index=0 and their `arguments` strings would
      // concatenate (`...}{"cmd":...`), producing un-decodable JSON.
      // When the index is missing, fall back to keying by `id`, and only
      // as a last resort assume continuation of the most-recent entry.
      final id = optionalStringFromValue(toolCallMap['id']) ?? '';
      final rawIndex = _readInt(toolCallMap['index']);
      final int index;
      if (rawIndex != null) {
        index = rawIndex;
      } else if (id.isNotEmpty) {
        int? matchedIndex;
        for (final entry in toolCalls.entries) {
          if (entry.value.id == id) {
            matchedIndex = entry.key;
            break;
          }
        }
        index = matchedIndex ?? toolCalls.length;
      } else if (toolCalls.isEmpty) {
        index = 0;
      } else {
        index = toolCalls.keys.reduce((a, b) => a > b ? a : b);
      }
      final entry = toolCalls.putIfAbsent(index, () => _MutableToolCall());
      if (id.isNotEmpty) {
        entry.id = id;
      }
      final function = toolCallMap['function'];
      if (function is Map) {
        final functionMap = stringKeyedMapFromValue(function);
        final name = optionalStringFromValue(functionMap['name']);
        if (name != null) {
          entry.name = name;
        }
        final argumentsFragment = '${functionMap['arguments'] ?? ''}';
        if (argumentsFragment.isNotEmpty) {
          entry.argumentsBuffer.write(argumentsFragment);
        }
        emitEvent(
          AiChatStreamEvent.toolCallDelta(
            AiToolCallDelta(
              index: index,
              id: entry.id,
              name: entry.name,
              argumentsFragment: argumentsFragment,
            ),
          ),
        );
      }
    }
  }
}

/// Processes a single SSE event block in Claude/Anthropic streaming format.
///
/// Claude SSE events use a top-level `type` field to indicate the event kind:
///   - `message_start` → initial message metadata + usage
///   - `ping` → heartbeat, ignored
///   - `content_block_start` → beginning of a content block (text/thinking)
///   - `content_block_delta` → incremental text/thinking content
///   - `content_block_stop` → end of current content block
///   - `message_delta` → stop_reason + final usage
///   - `message_stop` → end of message
void _processClaudeStreamEvent(
  Map<String, Object?> decoded, {
  required StringBuffer textBuffer,
  required StringBuffer reasoningBuffer,
  required Map<int, _MutableToolCall> toolCalls,
  required AiTokenUsage? Function() usage,
  required void Function(AiTokenUsage?) setUsage,
  required void Function(AiChatStreamEvent) emitEvent,
  required void Function(String) completeStreamResult,
  required void Function() cancelSubscription,
  required void Function(String) setFinishReason,
}) {
  final type = stringFromValue(decoded['type']);

  switch (type) {
    case 'message_start':
      // Extract initial usage from message_start.message.usage
      final message = decoded['message'];
      if (message is Map<String, Object?>) {
        final usageJson = message['usage'];
        if (usageJson is Map) {
          final usageMap = usageJson is Map<String, Object?>
              ? usageJson
              : stringKeyedMapFromValue(usageJson);
          final parsedUsage = AiTokenUsageParser.parseClaude(usageMap);
          if (parsedUsage != null && !parsedUsage.isEmpty) {
            final merged = AiTokenUsageParser.carryForward(
              usage(),
              parsedUsage,
            );
            setUsage(merged);
            emitEvent(AiChatStreamEvent.usage(merged));
          }
        }
      }

    case 'ping':
      break;

    case 'content_block_start':
      // Track tool_use blocks so we capture the tool id and name.
      final contentBlock = decoded['content_block'];
      if (contentBlock is Map<String, Object?>) {
        final blockType = stringFromValue(contentBlock['type']);
        if (blockType == 'tool_use') {
          final index = _readInt(decoded['index']) ?? toolCalls.length;
          final entry = toolCalls.putIfAbsent(index, () => _MutableToolCall());
          final id = optionalStringFromValue(contentBlock['id']);
          if (id != null) entry.id = id;
          final name = optionalStringFromValue(contentBlock['name']);
          if (name != null) entry.name = name;
        }
      }

    case 'content_block_delta':
      final delta = decoded['delta'];
      if (delta is! Map<String, Object?>) break;
      final deltaType = stringFromValue(delta['type']);
      if (deltaType == 'text_delta') {
        final text = '${delta['text'] ?? ''}';
        if (text.isNotEmpty) {
          textBuffer.write(text);
          emitEvent(AiChatStreamEvent.textDelta(text));
        }
      } else if (deltaType == 'thinking_delta') {
        final thinking = '${delta['thinking'] ?? ''}';
        if (thinking.isNotEmpty) {
          reasoningBuffer.write(thinking);
          emitEvent(AiChatStreamEvent.reasoningDelta(thinking));
        }
      } else if (deltaType == 'signature_delta') {
        // Signature blocks — ignore for now.
      } else if (deltaType == 'input_json_delta') {
        // Tool call argument fragment (Claude tool_use streaming).
        final partialJson = '${delta['partial_json'] ?? ''}';
        final index = _readInt(decoded['index']) ?? toolCalls.length;
        final entry = toolCalls.putIfAbsent(index, () => _MutableToolCall());
        if (partialJson.isNotEmpty) {
          entry.argumentsBuffer.write(partialJson);
          emitEvent(
            AiChatStreamEvent.toolCallDelta(
              AiToolCallDelta(
                index: index,
                id: entry.id,
                name: entry.name,
                argumentsFragment: partialJson,
              ),
            ),
          );
        }
      }

    case 'content_block_stop':
      break;

    case 'message_delta':
      // Final usage and stop_reason.
      final deltaPayload = decoded['delta'];
      if (deltaPayload is Map<String, Object?>) {
        final stopReason = optionalStringFromValue(deltaPayload['stop_reason']);
        if (stopReason != null) {
          setFinishReason(stopReason);
        }
      }
      final usageJson = decoded['usage'];
      if (usageJson is Map) {
        final usageMap = usageJson is Map<String, Object?>
            ? usageJson
            : stringKeyedMapFromValue(usageJson);
        final parsedUsage = AiTokenUsageParser.parseClaude(usageMap);
        if (parsedUsage != null && !parsedUsage.isEmpty) {
          // Merge with the message_start frame so cache_* fields are
          // preserved even when message_delta only ships output_tokens.
          final merged = AiTokenUsageParser.carryForward(usage(), parsedUsage);
          setUsage(merged);
          emitEvent(AiChatStreamEvent.usage(merged));
        }
      }

    case 'message_stop':
      completeStreamResult('claude_message_stop');
      cancelSubscription();

    case 'error':
      // The general in-stream error detection in processEventBlock handles
      // this case because the decoded map has an `error` key.
      break;

    default:
      break;
  }
}

/// Processes a single SSE event block in Gemini streaming format.
///
/// Gemini streaming (`?alt=sse`) returns the same JSON structure as non-
/// streaming but incrementally for each generated chunk:
/// ```json
/// {
///   "candidates": [{
///     "content": {
///       "parts": [{ "text": "..." }],
///       "role": "model"
///     }
///   }],
///   "usageMetadata": { ... }
/// }
/// ```
/// Tool calls appear as `functionCall` parts:
/// ```json
/// { "functionCall": { "name": "...", "args": {...} } }
/// ```
void _processGeminiStreamEvent(
  Map<String, Object?> decoded, {
  required StringBuffer textBuffer,
  required StringBuffer reasoningBuffer,
  required Map<int, _MutableToolCall> toolCalls,
  required AiTokenUsage? Function() usage,
  required void Function(AiTokenUsage?) setUsage,
  required void Function(AiChatStreamEvent) emitEvent,
  required void Function(String) setFinishReason,
}) {
  // Parse usage metadata.
  final usageJson = decoded['usageMetadata'];
  if (usageJson is Map) {
    final usageMap = usageJson is Map<String, Object?>
        ? usageJson
        : stringKeyedMapFromValue(usageJson);
    final parsedUsage = AiTokenUsageParser.parseGemini(usageMap);
    if (parsedUsage != null && !parsedUsage.isEmpty) {
      final merged = AiTokenUsageParser.carryForward(usage(), parsedUsage);
      setUsage(merged);
      emitEvent(AiChatStreamEvent.usage(merged));
    }
  }

  // Parse candidates.
  final candidates = decoded['candidates'];
  if (candidates is! List<dynamic>) return;
  for (final candidate in candidates) {
    if (candidate is! Map<String, Object?>) continue;
    // Capture finishReason from Gemini (e.g. "STOP", "MAX_TOKENS").
    final geminiFinishReason = optionalStringFromValue(
      candidate['finishReason'],
    );
    if (geminiFinishReason != null) {
      // Normalize Gemini's "MAX_TOKENS" to "length" for consistency.
      final normalized = geminiFinishReason.toUpperCase() == 'MAX_TOKENS'
          ? 'length'
          : geminiFinishReason.toLowerCase();
      setFinishReason(normalized);
    }
    final content = candidate['content'];
    if (content is! Map<String, Object?>) continue;
    final parts = content['parts'];
    if (parts is! List<dynamic>) continue;

    for (final part in parts) {
      if (part is! Map<String, Object?>) continue;

      // Text delta.
      final text = optionalStringFromValue(part['text']);
      if (text != null) {
        textBuffer.write(text);
        emitEvent(AiChatStreamEvent.textDelta(text));
        continue;
      }

      // Thinking / reasoning (Gemini 2.5 `thought` field).
      final thought = part['thought'];
      if (thought == true) {
        final thinkingText = '${part['text'] ?? ''}';
        if (thinkingText.isNotEmpty) {
          reasoningBuffer.write(thinkingText);
          emitEvent(AiChatStreamEvent.reasoningDelta(thinkingText));
          continue;
        }
      }

      // Function call (tool use).
      final functionCall = part['functionCall'];
      if (functionCall is Map<String, Object?>) {
        final name = optionalStringFromValue(functionCall['name']);
        if (name != null) {
          final index = toolCalls.length;
          final entry = toolCalls.putIfAbsent(index, () => _MutableToolCall());
          entry.id = 'gemini-tc-$index';
          entry.name = name;
          final args = functionCall['args'];
          final argsJson = args is Map ? jsonEncode(args) : '{}';
          entry.argumentsBuffer.write(argsJson);
          emitEvent(
            AiChatStreamEvent.toolCallDelta(
              AiToolCallDelta(
                index: index,
                id: entry.id,
                name: name,
                argumentsFragment: argsJson,
              ),
            ),
          );
        }
      }
    }
  }
}

class AiChatException implements Exception {
  const AiChatException(this.message, {this.telemetry});

  final String message;
  final AiChatRequestTelemetry? telemetry;

  @override
  String toString() => message;
}

class AiChatCancelledException implements Exception {
  const AiChatCancelledException([this.message = 'Request cancelled.']);

  final String message;

  @override
  String toString() => message;
}

bool _isOpenAiCompatibleProtocol(AiProtocolType protocol) {
  switch (protocol) {
    case AiProtocolType.openai:
    case AiProtocolType.qwen:
    case AiProtocolType.kimi:
    case AiProtocolType.glm:
    case AiProtocolType.grok:
    case AiProtocolType.deepseek:
    case AiProtocolType.seed:
    case AiProtocolType.stepfun:
    case AiProtocolType.minimax:
    case AiProtocolType.longcat:
    case AiProtocolType.agnes:
    case AiProtocolType.joycode:
    case AiProtocolType.wenxin:
    case AiProtocolType.meta:
    case AiProtocolType.mimo:
    case AiProtocolType.hunyuan:
    case AiProtocolType.vllm:
    case AiProtocolType.sglang:
    case AiProtocolType.ollama:
      return true;
    case AiProtocolType.gemini:
    case AiProtocolType.claude:
      return false;
  }
}

extension on AiChatService {
  Future<AiChatException> _decorateProviderProbeFailure(
    AiModelConfig model,
    AiChatException error, {
    required Duration timeout,
  }) async {
    final scanner = _modelScanner ?? AiModelScanner();
    final ownsScanner = identical(scanner, _modelScanner) == false;
    String? probeDiagnosis;
    try {
      final scanResult = await scanner.scan(model, timeout: timeout);
      final relayAvailabilityReason =
          AiTransportDiagnosticMessages.relayModelAvailabilityReason(
            error.message,
          );
      if (scanResult.isSuccess) {
        final ids = scanResult.modelIds;
        final modelId = nullIfBlank(model.modelId);
        final knownModel = modelId != null && ids.contains(modelId);
        final modelsLabel = ids.isEmpty
            ? StructuredErrorText.pick(
                zh: '模型列表接口可达，但未返回任何模型。',
                en: 'The models endpoint is reachable, but it returned no models.',
              )
            : knownModel
            ? StructuredErrorText.pick(
                zh: '模型列表接口可达，且已包含当前模型 ID。',
                en: 'The models endpoint is reachable and already includes the current model ID.',
              )
            : StructuredErrorText.pick(
                zh: '模型列表接口可达，但未找到当前模型 ID：${modelId ?? model.modelId}',
                en: 'The models endpoint is reachable, but it did not include the current model ID: ${modelId ?? model.modelId}',
              );
        final summary = relayAvailabilityReason != null
            ? StructuredErrorText.pick(
                zh: '这进一步说明网关本身在线，当前失败主要是模型分组或渠道可用性问题，而不是 Base URL 或协议不兼容。',
                en: 'This further suggests that the gateway itself is online, and the current failure is mainly about model-group or channel availability rather than the Base URL or protocol.',
              )
            : StructuredErrorText.pick(
                zh: '这通常说明网关本身在线，失败更可能出在聊天端点兼容性、模型权限或该模型在当前中转未实际开通。',
                en: 'This usually means the gateway itself is online, and the failure is more likely caused by chat-endpoint compatibility, model permissions, or the model not actually being enabled on the current relay.',
              );
        probeDiagnosis =
            '${StructuredErrorText.pick(zh: '探测补充：', en: 'Probe follow-up:')}\n$modelsLabel\n$summary';
      } else {
        final scanError = nullIfBlank(scanResult.error);
        if (scanError != null) {
          probeDiagnosis =
              '${StructuredErrorText.pick(zh: '探测补充：', en: 'Probe follow-up:')}\n${StructuredErrorText.pick(zh: '模型列表探测也失败了。该 Base URL 可能整体不可用、鉴权方式不匹配，或中转未按 OpenAI 兼容形式暴露接口。', en: 'The models probe also failed. The Base URL may be entirely unavailable, the authentication scheme may not match, or the relay may not expose the interface in an OpenAI-compatible form.')}\n$scanError';
        }
      }
    } catch (_) {
      // Keep the original provider-test failure as the primary signal.
    } finally {
      if (ownsScanner) {
        scanner.dispose();
      }
    }

    final detail = _buildProviderProbeDetail(
      error.message,
      telemetry: error.telemetry,
      diagnosis: probeDiagnosis,
    );
    return AiChatException(detail, telemetry: error.telemetry);
  }
}

String _buildProviderProbeDetail(
  String message, {
  AiChatRequestTelemetry? telemetry,
  String? diagnosis,
}) {
  final base = nullIfBlank(message) ?? 'Unknown provider probe failure.';
  final extraLines = <String>[];
  final method = nullIfBlank(telemetry?.requestMethod);
  final url = nullIfBlank(telemetry?.requestUrl);
  if (method != null) {
    extraLines.add(
      StructuredErrorText.pick(zh: '请求方法：$method', en: 'Method: $method'),
    );
  }
  if (url != null) {
    extraLines.add(StructuredErrorText.pick(zh: '请求地址：$url', en: 'URL: $url'));
  }
  final trimmedDiagnosis = nullIfBlank(diagnosis);
  if (trimmedDiagnosis != null) {
    extraLines.add(trimmedDiagnosis);
  }
  if (extraLines.isEmpty) {
    return base;
  }
  return '$base\n${extraLines.join('\n')}';
}

class _MutableToolCall {
  String id = '';
  String name = '';
  final StringBuffer argumentsBuffer = StringBuffer();
}

const int _maxAiChatRedirects = 4;

Future<http.StreamedResponse> _sendHttpRequestWithRedirects({
  required http.Client client,
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  String? body,
  required Duration timeout,
}) async {
  var currentMethod = method;
  var currentUri = uri;
  var currentBody = body;
  final currentHeaders = Map<String, String>.from(headers);

  for (var redirectCount = 0; ; redirectCount++) {
    final request = http.Request(currentMethod, currentUri)
      ..followRedirects = false
      ..headers.addAll(currentHeaders);
    if (currentBody != null) {
      request.body = currentBody;
    }

    final response = await client.send(request).timeout(timeout);
    if (!isRedirectStatusCode(response.statusCode)) {
      return response;
    }

    final redirectLocation = readResponseHeader(response.headers, 'location');
    if (redirectLocation.isEmpty) {
      return response;
    }
    if (redirectCount >= _maxAiChatRedirects) {
      final responseBody = await response.stream.bytesToString();
      final responseText = nullIfBlank(responseBody);
      throw AiChatException(
        'Too many redirects (${_maxAiChatRedirects + 1})${responseText == null ? '' : ': $responseText'}',
      );
    }

    await response.stream.drain<void>();
    final redirectedUri = currentUri.resolve(redirectLocation);
    if (isCrossOriginRedirect(currentUri, redirectedUri)) {
      _stripSensitiveRedirectHeaders(currentHeaders);
    }
    currentUri = redirectedUri;
    if (response.statusCode == 303 &&
        currentMethod != 'GET' &&
        currentMethod != 'HEAD') {
      currentMethod = 'GET';
      currentBody = null;
    }
  }
}

void _stripSensitiveRedirectHeaders(Map<String, String> headers) {
  const sensitiveHeaderNames = <String>{
    'authorization',
    'cookie',
    'proxy-authorization',
    'x-api-key',
    'api-key',
  };
  headers.removeWhere(
    (name, value) => sensitiveHeaderNames.contains(name.toLowerCase()),
  );
}

String _extractStreamText(Object? rawContent) {
  if (rawContent is String) {
    return rawContent;
  }
  if (rawContent is List) {
    final buffer = StringBuffer();
    for (final item in rawContent) {
      if (item is String) {
        buffer.write(item);
        continue;
      }
      if (item is! Map) {
        continue;
      }
      final itemMap = stringKeyedMapFromValue(item);
      final text = '${itemMap['text'] ?? itemMap['content'] ?? ''}';
      if (text.isNotEmpty) {
        buffer.write(text);
      }
    }
    return buffer.toString();
  }
  return '';
}

String _extractReasoningText(Map<String, Object?> delta) {
  final directReasoning =
      _extractStreamText(delta['reasoning_content']) +
      _extractStreamText(delta['reasoning']);
  if (directReasoning.isNotEmpty) {
    return directReasoning;
  }
  final reasoningDetails = delta['reasoning_details'];
  if (reasoningDetails is! List) {
    return '';
  }
  final buffer = StringBuffer();
  for (final item in reasoningDetails) {
    if (item is! Map) {
      continue;
    }
    final itemMap = stringKeyedMapFromValue(item);
    final text = '${itemMap['text'] ?? itemMap['content'] ?? ''}';
    if (text.isNotEmpty) {
      buffer.write(text);
    }
  }
  return buffer.toString();
}

class _StreamingGeneratedMedia {
  const _StreamingGeneratedMedia({required this.url, required this.kind});

  final String url;
  final String kind;

  String toMarkdown() {
    return switch (kind) {
      'image' => '![AI Generated Image]($url)',
      'audio' => '[AI Generated Audio]($url)',
      'video' => '[AI Generated Video]($url)',
      _ => '[AI Generated Media]($url)',
    };
  }
}

_StreamingGeneratedMedia? _extractStreamingGeneratedMedia(Object? value) {
  return _visitStreamingMediaNode(value, allowBareStringMedia: true);
}

const int _maxStreamingMediaUrlChars = 32 * 1024;

_StreamingGeneratedMedia? _visitStreamingMediaNode(
  Object? node, {
  String? hintedKind,
  bool allowBareStringMedia = false,
  bool allowHintedKindWithoutExtension = false,
}) {
  if (node == null) return null;
  if (node is String) {
    if (!allowBareStringMedia) return null;
    return _streamingGeneratedMediaFromUrl(
      node,
      hintedKind: hintedKind,
      allowHintedKindWithoutExtension: allowHintedKindWithoutExtension,
    );
  }
  if (node is List) {
    for (final item in node) {
      final found = _visitStreamingMediaNode(
        item,
        hintedKind: hintedKind,
        allowBareStringMedia: allowBareStringMedia,
        allowHintedKindWithoutExtension: allowHintedKindWithoutExtension,
      );
      if (found != null) return found;
    }
    return null;
  }
  if (node is Map) {
    return _visitStreamingMediaMap(
      node,
      hintedKind: hintedKind,
      allowHintedKindWithoutExtension: allowHintedKindWithoutExtension,
    );
  }
  return null;
}

_StreamingGeneratedMedia? _visitStreamingMediaMap(
  Map<dynamic, dynamic> rawMap, {
  String? hintedKind,
  bool allowHintedKindWithoutExtension = false,
}) {
  final map = <String, Object?>{};
  for (final entry in rawMap.entries) {
    final key = entry.key;
    if (key is String) {
      map[key] = entry.value;
    }
  }
  if (map.isEmpty) return null;

  final explicitMime = _firstNonEmptyString(map, const <String>[
    'mime_type',
    'mimeType',
    'content_type',
    'contentType',
    'media_type',
    'mediaType',
  ]);
  final mimeKind = _streamingMediaKindFromMime(explicitMime ?? '');
  final typeKind = _streamingMediaKindFromType(
    _firstNonEmptyString(map, const <String>[
          'type',
          'kind',
          'media_kind',
          'mediaKind',
          'object',
        ]) ??
        '',
  );
  final explicitKind = hintedKind ?? mimeKind ?? typeKind;

  for (final key in const <String>[
    'video_url',
    'videoUrl',
    'generated_video',
    'generatedVideo',
    'audio_url',
    'audioUrl',
    'image_url',
    'imageUrl',
    'file_url',
    'fileUrl',
    'asset_url',
    'assetUrl',
    'download_url',
    'downloadUrl',
    'result_url',
    'resultUrl',
    'video',
    'audio',
    'image',
    'url',
    'uri',
    'data',
  ]) {
    if (!map.containsKey(key)) continue;
    final fieldKind = _streamingMediaKindFromField(key);
    final found = _visitStreamingMediaNode(
      map[key],
      hintedKind: fieldKind ?? explicitKind,
      allowBareStringMedia: true,
      allowHintedKindWithoutExtension:
          fieldKind != null ||
          mimeKind != null ||
          allowHintedKindWithoutExtension,
    );
    if (found != null) return found;
  }

  for (final key in const <String>[
    'choices',
    'delta',
    'message',
    'output',
    'result',
    'results',
    'content',
    'media',
    'file',
    'files',
    'artifact',
    'artifacts',
  ]) {
    final found = _visitStreamingMediaNode(
      map[key],
      hintedKind: explicitKind,
      allowHintedKindWithoutExtension:
          mimeKind != null || allowHintedKindWithoutExtension,
    );
    if (found != null) return found;
  }
  return null;
}

String? _firstNonEmptyString(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String) {
      final normalized = nullIfBlank(value);
      if (normalized != null) return normalized;
    }
  }
  return null;
}

_StreamingGeneratedMedia? _streamingGeneratedMediaFromUrl(
  String value, {
  String? hintedKind,
  bool allowHintedKindWithoutExtension = false,
}) {
  final trimmed = nullIfBlank(value);
  if (trimmed == null || trimmed.length > _maxStreamingMediaUrlChars) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  final extension = p.extension(uri.path).toLowerCase();
  final extensionKind = switch (extension) {
    '.png' || '.jpg' || '.jpeg' || '.gif' || '.webp' => 'image',
    '.mp4' || '.webm' || '.mov' || '.m4v' || '.mkv' => 'video',
    '.mp3' ||
    '.wav' ||
    '.m4a' ||
    '.aac' ||
    '.ogg' ||
    '.opus' ||
    '.flac' => 'audio',
    _ => null,
  };
  final kind =
      extensionKind ?? (allowHintedKindWithoutExtension ? hintedKind : null);
  if (kind == null) return null;
  return _StreamingGeneratedMedia(url: trimmed, kind: kind);
}

String? _streamingMediaKindFromMime(String mimeType) {
  final normalized = lowercaseStringFromValue(mimeType);
  if (normalized.startsWith('image/')) return 'image';
  if (normalized.startsWith('video/')) return 'video';
  if (normalized.startsWith('audio/')) return 'audio';
  return null;
}

String? _streamingMediaKindFromType(String value) {
  final normalized = lowercaseStringFromValue(value);
  if (normalized.contains('image')) return 'image';
  if (normalized.contains('video')) return 'video';
  if (normalized.contains('audio')) return 'audio';
  return null;
}

String? _streamingMediaKindFromField(String key) {
  return _streamingMediaKindFromType(key.replaceAll('_', '-'));
}

int? _readInt(Object? value) {
  return optionalIntegralIntFromValue(value);
}
