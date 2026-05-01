import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../app/support/silent_log.dart';
import '../../../shared/net/http_redirect_utils.dart';
import '../model/ai_creation_mode.dart';
import '../model/ai_model_config.dart';
import '../model/ai_token_usage.dart';
import 'ai_dsml_tool_call_parser.dart';
import 'ai_image_generation_service.dart';
import 'ai_protocol_adapter.dart';

abstract class AiChatClient {
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools,
    List<String> responseModalities,
    AiCreationRequest creationRequest,
    Duration timeout,
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
  });

  Future<String> testModel(AiModelConfig model);

  void dispose();
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
    if (finishReason == null) return false;
    final normalized = finishReason!.trim().toLowerCase();
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
  AiChatService({http.Client? client, AiImageGenerationService? imageService})
    : _client = client ?? http.Client(),
      _imageService = imageService ?? AiImageGenerationService(client: client);

  static const String _availabilityProbePrompt =
      'Reply with OK only if this model configuration works.';
  static const Duration _streamIdleWarningInterval = Duration(seconds: 4);

  /// Defensive cap for the SSE line buffer. A well-behaved server delimits
  /// events with `\n\n`, keeping per-block size in the KB range. If a buggy
  /// or hostile server streams megabytes without a delimiter we discard the
  /// pending buffer instead of letting it grow without bound and OOM the
  /// process. 4 MiB is far above any realistic single-event size while
  /// remaining cheap to retain.
  int maxStreamLineBufferBytes = 4 * 1024 * 1024;

  final http.Client _client;
  final AiImageGenerationService _imageService;

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
      final parts = turn.effectiveParts
          .where((p) => p.kind == AiChatContentPartKind.text)
          .map((p) => (p.text ?? '').trim())
          .where((t) => t.isNotEmpty)
          .join('\n');
      if (parts.isNotEmpty) {
        return parts.replaceFirst(_structuredPromptHeaderPattern, '').trim();
      }
    }
    return '';
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
    final result = switch (creationRequest.mode) {
      AiCreationMode.image => await _imageService.generateImage(
        model: model,
        prompt: prompt,
        options: creationRequest.options,
        timeout: timeout,
      ),
      AiCreationMode.video => await _imageService.generateVideo(
        model: model,
        prompt: prompt,
        options: creationRequest.options,
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
  }) async {
    _assertCreationModeIsRoutable(model, creationRequest);
    if (_shouldDivertToMediaEndpoint(model, creationRequest)) {
      try {
        return await _sendMediaGenerationCompletion(
          model: model,
          messages: messages,
          creationRequest: creationRequest,
          timeout: timeout,
        );
      } on AiMediaGenerationException catch (error) {
        throw AiChatException(error.message);
      }
    }
    try {
      final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
      final blueprint = await adapter.buildChatRequest(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
      );
      final effectiveMethod = model.requestMethod.trim().isNotEmpty
          ? model.requestMethod.trim()
          : 'POST';
      final startedAt = DateTime.now().toUtc();
      final response = await http.Response.fromStream(
        await _sendHttpRequestWithRedirects(
          client: _client,
          method: effectiveMethod,
          uri: Uri.parse(blueprint.url),
          headers: blueprint.headers,
          body: jsonEncode(blueprint.body),
          timeout: timeout,
        ),
      );
      final endedAt = DateTime.now().toUtc();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorMessage = adapter.extractErrorMessage(response.body);
        throw AiChatException(
          _ChatErrorMessages.httpStatus(
            response.statusCode,
            serverMessage: errorMessage,
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
            reasoningText != null && parsedReply.trim() == reasoningText.trim();
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
        throw AiChatException(error.message);
      }
    } on TimeoutException {
      throw AiChatException(_ChatErrorMessages.timeout(timeout));
    } on HandshakeException catch (error) {
      throw AiChatException(_ChatErrorMessages.handshake(error));
    } on TlsException catch (error) {
      throw AiChatException(_ChatErrorMessages.tls(error));
    } on SocketException catch (error) {
      throw AiChatException(_ChatErrorMessages.socket(error));
    } on http.ClientException catch (error) {
      throw AiChatException(_ChatErrorMessages.httpClient(error));
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
      final reasoning = message['reasoning_content'];
      if (reasoning is String && reasoning.trim().isNotEmpty) {
        return reasoning.trim();
      }
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
  }) async {
    _assertCreationModeIsRoutable(model, creationRequest);
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
      );
    }
    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    if (!adapter.supportsServerStreaming) {
      _debugAiStreamLog(
        'model=${model.modelId} using synthetic stream adapter=${adapter.runtimeType}',
      );
      return _sendMessageAsSyntheticStream(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        creationRequest: creationRequest,
        timeout: timeout,
        cancelSignal: cancelSignal,
      );
    }
    final isClaudeProtocol = adapter is ClaudeProtocolAdapter;
    final isGeminiProtocol = adapter is GeminiProtocolAdapter;

    final blueprint = await adapter.buildChatRequest(
      model: model,
      messages: messages,
      tools: tools,
      responseModalities: responseModalities,
      stream: true,
    );
    final effectiveMethod = model.requestMethod.trim().isNotEmpty
        ? model.requestMethod.trim()
        : 'POST';
    final streamStartedAt = DateTime.now().toUtc();
    final capturedHeaders = Map<String, String>.unmodifiable(blueprint.headers);
    final capturedBody = blueprint.body;
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
    late final http.StreamedResponse streamedResponse;
    try {
      if (cancelSignal == null) {
        streamedResponse = await streamedResponseFuture;
      } else {
        final firstResult = await Future.any(<Future<Object?>>[
          streamedResponseFuture,
          cancelSignal.then((_) => _cancelledStreamSentinel),
        ]);
        if (identical(firstResult, _cancelledStreamSentinel)) {
          _debugAiStreamLog(
            'model=${model.modelId} stream_cancelled_before_connect',
          );
          unawaited(
            streamedResponseFuture
                .then((response) => response.stream.drain<void>())
                .catchError((Object _, StackTrace stackTrace) {}),
          );
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
    } on TimeoutException {
      throw AiChatException(_ChatErrorMessages.timeout(timeout));
    } on HandshakeException catch (error) {
      throw AiChatException(_ChatErrorMessages.handshake(error));
    } on TlsException catch (error) {
      throw AiChatException(_ChatErrorMessages.tls(error));
    } on SocketException catch (error) {
      throw AiChatException(_ChatErrorMessages.socket(error));
    } on http.ClientException catch (error) {
      throw AiChatException(_ChatErrorMessages.httpClient(error));
    }
    _debugAiStreamLog(
      'model=${model.modelId} stream_connected status=${streamedResponse.statusCode} url=${streamedResponse.request?.url ?? blueprint.url}',
    );

    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      final errorBody = await streamedResponse.stream.bytesToString();
      final errorMessage = adapter.extractErrorMessage(errorBody);
      throw AiChatException(
        _ChatErrorMessages.httpStatus(
          streamedResponse.statusCode,
          serverMessage: errorMessage,
        ),
      );
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
    Timer? idleWarningTimer;
    var idleWarningBucket = 0;
    var lastActivityAt = DateTime.now().toUtc();
    var lastActivityLabel = 'connected';

    bool canEmitEvents() {
      return !resultCompleter.isCompleted && !eventController.isClosed;
    }

    void markStreamActivity(String label) {
      lastActivityAt = DateTime.now().toUtc();
      lastActivityLabel = label;
      idleWarningBucket = 0;
    }

    void startIdleWarningTimer() {
      idleWarningTimer?.cancel();
      idleWarningTimer = Timer.periodic(_streamIdleWarningInterval, (_) {
        if (resultCompleter.isCompleted) {
          return;
        }
        final idleMs = DateTime.now()
            .toUtc()
            .difference(lastActivityAt)
            .inMilliseconds;
        final nextBucket = idleMs ~/ _streamIdleWarningInterval.inMilliseconds;
        if (nextBucket <= 0 || nextBucket == idleWarningBucket) {
          return;
        }
        idleWarningBucket = nextBucket;
        _debugAiStreamLog(
          'model=${model.modelId} stream_idle_warning idle_ms=$idleMs last_activity=$lastActivityLabel line_buffer=${lineBuffer.length} raw_chars=${rawResponseBuffer.length} reply_chars=${textBuffer.length} reasoning_chars=${reasoningBuffer.length} tool_calls=${toolCalls.length}',
        );
      });
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
      markStreamActivity('generated_media');
      _debugAiStreamLog(
        'model=${model.modelId} generated_media kind=${media.kind} url=${media.url}',
      );
      emitEvent(AiChatStreamEvent.textDelta(delta));
    }

    void completeStreamResult(String reason, {bool wasCancelled = false}) {
      if (resultCompleter.isCompleted) {
        return;
      }
      idleWarningTimer?.cancel();
      idleWarningTimer = null;
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
          .where((item) => item.name.trim().isNotEmpty)
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
      _debugAiStreamLog(
        'model=${model.modelId} stream_complete reason=$reason cancelled=$wasCancelled finish_reason=${effectiveFinishReason ?? 'unknown'} trailing_incomplete_dsml=${dsmlExtraction.hasTrailingIncompleteMarkup} reply_chars=${textBuffer.length} reasoning_chars=${reasoningBuffer.length} tool_calls=${resolvedToolCalls.length}',
      );
      if (!eventController.isClosed) {
        unawaited(eventController.close());
      }
    }

    void processEventBlock(String block) {
      if (resultCompleter.isCompleted) {
        return;
      }
      final trimmedBlock = block.trim();
      if (trimmedBlock.isEmpty) {
        return;
      }
      final dataLines = trimmedBlock
          .split('\n')
          .where((line) => line.startsWith('data:'))
          .map((line) => line.substring(5).trim())
          .toList(growable: false);
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
          idleWarningTimer?.cancel();
          idleWarningTimer = null;
          _debugAiStreamLog(
            'model=${model.modelId} in_stream_error error=$errorMessage',
          );
          if (!resultCompleter.isCompleted) {
            resultCompleter.completeError(
              AiChatException('API error: $errorMessage'),
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
          markStreamActivity: markStreamActivity,
          emitEvent: emitEvent,
          completeStreamResult: (reason) => completeStreamResult(reason),
          cancelSubscription: () {
            unawaited(responseSubscription?.cancel());
          },
          setFinishReason: (value) => finishReason = value,
          model: model,
        );
      } else if (isGeminiProtocol) {
        _processGeminiStreamEvent(
          decoded,
          textBuffer: textBuffer,
          reasoningBuffer: reasoningBuffer,
          toolCalls: toolCalls,
          usage: () => usage,
          setUsage: (value) => usage = value,
          markStreamActivity: markStreamActivity,
          emitEvent: emitEvent,
          setFinishReason: (value) => finishReason = value,
          model: model,
        );
      } else {
        _processOpenAiStreamEvent(
          decoded,
          textBuffer: textBuffer,
          reasoningBuffer: reasoningBuffer,
          toolCalls: toolCalls,
          usage: () => usage,
          setUsage: (value) => usage = value,
          markStreamActivity: markStreamActivity,
          emitEvent: emitEvent,
          setFinishReason: (value) => finishReason = value,
          model: model,
        );
      }
    }

    void processChunk(String chunk) {
      markStreamActivity('chunk');
      lineBuffer.write(chunk.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
      // Defensive cap: if the buffer exceeds the threshold without a
      // `\n\n` delimiter, the upstream is misbehaving (or sending a single
      // event larger than any practical SSE payload). Drop the pending
      // bytes so we don't keep growing memory while the connection idles.
      if (lineBuffer.length > maxStreamLineBufferBytes) {
        _debugAiStreamLog(
          'model=${model.modelId} stream_line_buffer_overflow_dropped bytes=${lineBuffer.length}',
        );
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
            idleWarningTimer?.cancel();
            idleWarningTimer = null;
            _debugAiStreamLog(
              'model=${model.modelId} stream_error error=$error',
            );
            if (!resultCompleter.isCompleted) {
              resultCompleter.completeError(
                error is TimeoutException
                    ? const AiChatException('Request timed out.')
                    : AiChatException('$error'),
                stackTrace,
              );
            }
            if (!eventController.isClosed) {
              unawaited(eventController.close());
            }
          },
          onDone: () {
            idleWarningTimer?.cancel();
            idleWarningTimer = null;
            if (lineBuffer.isNotEmpty) {
              processEventBlock(lineBuffer.toString());
            }
            completeStreamResult('stream_closed');
          },
          cancelOnError: true,
        );
    startIdleWarningTimer();

    return AiChatStreamingResponse(
      events: eventController.stream,
      result: resultCompleter.future,
      cancel: () async {
        idleWarningTimer?.cancel();
        idleWarningTimer = null;
        _debugAiStreamLog('model=${model.modelId} cancel_requested');
        completeStreamResult('cancelled', wasCancelled: true);
        await responseSubscription?.cancel();
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

  @override
  Future<String> testModel(AiModelConfig model) async {
    if (model.normalizedBaseUrl.isEmpty) {
      throw const AiChatException('Missing base URL.');
    }
    if (model.modelId.trim().isEmpty) {
      throw const AiChatException('Missing model ID.');
    }
    final reply = await sendMessage(
      model: model,
      messages: const <AiChatTurn>[
        AiChatTurn(role: AiChatRole.user, content: _availabilityProbePrompt),
      ],
      timeout: const Duration(seconds: 20),
    );
    final normalizedReply = reply.reply.trim();
    if (normalizedReply.isEmpty) {
      throw const AiChatException('Empty assistant reply.');
    }
    return normalizedReply;
  }

  @override
  void dispose() {
    _imageService.dispose();
    _client.close();
  }
}

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
  required void Function(String) markStreamActivity,
  required void Function(AiChatStreamEvent) emitEvent,
  required void Function(String) setFinishReason,
  required AiModelConfig model,
}) {
  final usageJson = decoded['usage'];
  if (usageJson is Map || usageJson is Map<String, Object?>) {
    final usageMap = usageJson is Map<String, Object?>
        ? usageJson
        : Map<String, Object?>.from(usageJson as Map);
    final parsedUsage = AiTokenUsage(
      promptTokens: _readInt(usageMap['prompt_tokens']),
      completionTokens: _readInt(usageMap['completion_tokens']),
      totalTokens: _readInt(usageMap['total_tokens']),
    );
    if (!parsedUsage.isEmpty) {
      setUsage(parsedUsage);
      markStreamActivity('usage');
      _debugAiStreamLog(
        'model=${model.modelId} usage prompt=${parsedUsage.promptTokens ?? 0} completion=${parsedUsage.completionTokens ?? 0} total=${parsedUsage.totalTokens ?? 0}',
      );
      emitEvent(AiChatStreamEvent.usage(parsedUsage));
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
    final choiceFinishReason = '${choice['finish_reason'] ?? ''}'.trim();
    if (choiceFinishReason.isNotEmpty) {
      setFinishReason(choiceFinishReason);
      markStreamActivity('finish_reason');
      _debugAiStreamLog(
        'model=${model.modelId} finish_reason=$choiceFinishReason',
      );
    }
    final delta = choice['delta'];
    if (delta is! Map<String, Object?>) {
      continue;
    }
    final textDelta = _extractStreamText(delta['content']);
    if (textDelta.isNotEmpty) {
      textBuffer.write(textDelta);
      markStreamActivity('text_delta');
      _debugAiStreamLog(
        'model=${model.modelId} text_delta chars=${textDelta.length}',
      );
      emitEvent(AiChatStreamEvent.textDelta(textDelta));
    }
    final reasoningDelta = _extractReasoningText(delta);
    if (reasoningDelta.isNotEmpty) {
      reasoningBuffer.write(reasoningDelta);
      markStreamActivity('reasoning_delta');
      _debugAiStreamLog(
        'model=${model.modelId} reasoning_delta chars=${reasoningDelta.length}',
      );
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
      final toolCallMap = Map<String, Object?>.from(rawToolCall);
      // OpenAI streaming spec assigns each tool_call a stable `index`.
      // Some non-strict OpenAI-compatible providers omit it and instead
      // ship two complete tool_calls in a single chunk — both would then
      // bucket into index=0 and their `arguments` strings would
      // concatenate (`...}{"cmd":...`), producing un-decodable JSON.
      // When the index is missing, fall back to keying by `id`, and only
      // as a last resort assume continuation of the most-recent entry.
      final id = '${toolCallMap['id'] ?? ''}'.trim();
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
        final functionMap = Map<String, Object?>.from(function);
        final name = '${functionMap['name'] ?? ''}'.trim();
        if (name.isNotEmpty) {
          entry.name = name;
        }
        final argumentsFragment = '${functionMap['arguments'] ?? ''}';
        if (argumentsFragment.isNotEmpty) {
          entry.argumentsBuffer.write(argumentsFragment);
        }
        markStreamActivity('tool_call_delta');
        _debugAiStreamLog(
          'model=${model.modelId} tool_call_delta index=$index name=${entry.name} arg_chars=${argumentsFragment.length}',
        );
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
  required void Function(String) markStreamActivity,
  required void Function(AiChatStreamEvent) emitEvent,
  required void Function(String) completeStreamResult,
  required void Function() cancelSubscription,
  required void Function(String) setFinishReason,
  required AiModelConfig model,
}) {
  final type = '${decoded['type'] ?? ''}'.trim();

  switch (type) {
    case 'message_start':
      // Extract initial usage from message_start.message.usage
      final message = decoded['message'];
      if (message is Map<String, Object?>) {
        final usageJson = message['usage'];
        if (usageJson is Map) {
          final usageMap = usageJson is Map<String, Object?>
              ? usageJson
              : Map<String, Object?>.from(usageJson);
          final promptTokens = _readInt(usageMap['input_tokens']);
          final completionTokens = _readInt(usageMap['output_tokens']);
          final parsedUsage = AiTokenUsage(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: (promptTokens ?? 0) + (completionTokens ?? 0),
            cacheCreationTokens: _readInt(
              usageMap['cache_creation_input_tokens'],
            ),
            cacheReadTokens: _readInt(usageMap['cache_read_input_tokens']),
          );
          if (!parsedUsage.isEmpty) {
            setUsage(parsedUsage);
            markStreamActivity('usage');
            emitEvent(AiChatStreamEvent.usage(parsedUsage));
          }
        }
      }

    case 'ping':
      // Heartbeat — just mark activity.
      markStreamActivity('ping');

    case 'content_block_start':
      // Track tool_use blocks so we capture the tool id and name.
      final contentBlock = decoded['content_block'];
      if (contentBlock is Map<String, Object?>) {
        final blockType = '${contentBlock['type'] ?? ''}'.trim();
        if (blockType == 'tool_use') {
          final index = _readInt(decoded['index']) ?? toolCalls.length;
          final entry = toolCalls.putIfAbsent(index, () => _MutableToolCall());
          final id = '${contentBlock['id'] ?? ''}'.trim();
          if (id.isNotEmpty) entry.id = id;
          final name = '${contentBlock['name'] ?? ''}'.trim();
          if (name.isNotEmpty) entry.name = name;
        }
      }
      markStreamActivity('content_block_start');

    case 'content_block_delta':
      final delta = decoded['delta'];
      if (delta is! Map<String, Object?>) break;
      final deltaType = '${delta['type'] ?? ''}'.trim();
      if (deltaType == 'text_delta') {
        final text = '${delta['text'] ?? ''}';
        if (text.isNotEmpty) {
          textBuffer.write(text);
          markStreamActivity('text_delta');
          _debugAiStreamLog(
            'model=${model.modelId} claude_text_delta chars=${text.length}',
          );
          emitEvent(AiChatStreamEvent.textDelta(text));
        }
      } else if (deltaType == 'thinking_delta') {
        final thinking = '${delta['thinking'] ?? ''}';
        if (thinking.isNotEmpty) {
          reasoningBuffer.write(thinking);
          markStreamActivity('reasoning_delta');
          _debugAiStreamLog(
            'model=${model.modelId} claude_thinking_delta chars=${thinking.length}',
          );
          emitEvent(AiChatStreamEvent.reasoningDelta(thinking));
        }
      } else if (deltaType == 'signature_delta') {
        // Signature blocks — ignore for now.
        markStreamActivity('signature_delta');
      } else if (deltaType == 'input_json_delta') {
        // Tool call argument fragment (Claude tool_use streaming).
        final partialJson = '${delta['partial_json'] ?? ''}';
        final index = _readInt(decoded['index']) ?? toolCalls.length;
        final entry = toolCalls.putIfAbsent(index, () => _MutableToolCall());
        if (partialJson.isNotEmpty) {
          entry.argumentsBuffer.write(partialJson);
          markStreamActivity('tool_call_delta');
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
      markStreamActivity('content_block_stop');

    case 'message_delta':
      // Final usage and stop_reason.
      final deltaPayload = decoded['delta'];
      if (deltaPayload is Map<String, Object?>) {
        final stopReason = '${deltaPayload['stop_reason'] ?? ''}'.trim();
        if (stopReason.isNotEmpty) {
          setFinishReason(stopReason);
          markStreamActivity('stop_reason');
          _debugAiStreamLog(
            'model=${model.modelId} claude_stop_reason=$stopReason',
          );
        }
      }
      final usageJson = decoded['usage'];
      if (usageJson is Map) {
        final usageMap = usageJson is Map<String, Object?>
            ? usageJson
            : Map<String, Object?>.from(usageJson);
        final inputTokens = _readInt(usageMap['input_tokens']);
        final outputTokens = _readInt(usageMap['output_tokens']);
        final parsedUsage = AiTokenUsage(
          promptTokens: inputTokens,
          completionTokens: outputTokens,
          totalTokens: (inputTokens ?? 0) + (outputTokens ?? 0),
          cacheCreationTokens: _readInt(
            usageMap['cache_creation_input_tokens'],
          ),
          cacheReadTokens: _readInt(usageMap['cache_read_input_tokens']),
        );
        if (!parsedUsage.isEmpty) {
          setUsage(parsedUsage);
          markStreamActivity('usage');
          _debugAiStreamLog(
            'model=${model.modelId} claude_usage input=${parsedUsage.promptTokens ?? 0} output=${parsedUsage.completionTokens ?? 0}',
          );
          emitEvent(AiChatStreamEvent.usage(parsedUsage));
        }
      }

    case 'message_stop':
      markStreamActivity('message_stop');
      completeStreamResult('claude_message_stop');
      cancelSubscription();

    case 'error':
      // Claude sends error events with {"type": "error", "error": {...}}.
      final errorPayload = decoded['error'];
      String errorMessage = '';
      if (errorPayload is Map<String, Object?>) {
        errorMessage = '${errorPayload['message'] ?? ''}'.trim();
        if (errorMessage.isEmpty) {
          errorMessage = '$errorPayload';
        }
      } else if (errorPayload != null) {
        errorMessage = '$errorPayload';
      }
      if (errorMessage.isNotEmpty) {
        _debugAiStreamLog(
          'model=${model.modelId} claude_error error=$errorMessage',
        );
      }
      // The general in-stream error detection in processEventBlock will
      // handle this case since the decoded map has an 'error' key.
      markStreamActivity('error');

    default:
      // Unknown event type — log and ignore.
      _debugAiStreamLog(
        'model=${model.modelId} claude_unknown_event type=$type',
      );
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
  required void Function(String) markStreamActivity,
  required void Function(AiChatStreamEvent) emitEvent,
  required void Function(String) setFinishReason,
  required AiModelConfig model,
}) {
  // Parse usage metadata.
  final usageJson = decoded['usageMetadata'];
  if (usageJson is Map) {
    final usageMap = usageJson is Map<String, Object?>
        ? usageJson
        : Map<String, Object?>.from(usageJson);
    final parsedUsage = AiTokenUsage(
      promptTokens: _readInt(usageMap['promptTokenCount']),
      completionTokens: _readInt(usageMap['candidatesTokenCount']),
      totalTokens: _readInt(usageMap['totalTokenCount']),
      cacheReadTokens: _readInt(usageMap['cachedContentTokenCount']),
    );
    if (!parsedUsage.isEmpty) {
      setUsage(parsedUsage);
      markStreamActivity('usage');
      emitEvent(AiChatStreamEvent.usage(parsedUsage));
    }
  }

  // Parse candidates.
  final candidates = decoded['candidates'];
  if (candidates is! List<dynamic>) return;
  for (final candidate in candidates) {
    if (candidate is! Map<String, Object?>) continue;
    // Capture finishReason from Gemini (e.g. "STOP", "MAX_TOKENS").
    final geminiFinishReason = '${candidate['finishReason'] ?? ''}'.trim();
    if (geminiFinishReason.isNotEmpty) {
      // Normalize Gemini's "MAX_TOKENS" to "length" for consistency.
      final normalized = geminiFinishReason.toUpperCase() == 'MAX_TOKENS'
          ? 'length'
          : geminiFinishReason.toLowerCase();
      setFinishReason(normalized);
      markStreamActivity('finish_reason');
      _debugAiStreamLog(
        'model=${model.modelId} gemini_finish_reason=$geminiFinishReason',
      );
    }
    final content = candidate['content'];
    if (content is! Map<String, Object?>) continue;
    final parts = content['parts'];
    if (parts is! List<dynamic>) continue;

    for (final part in parts) {
      if (part is! Map<String, Object?>) continue;

      // Text delta.
      final text = '${part['text'] ?? ''}'.trim();
      if (text.isNotEmpty) {
        textBuffer.write(text);
        markStreamActivity('text_delta');
        _debugAiStreamLog(
          'model=${model.modelId} gemini_text_delta chars=${text.length}',
        );
        emitEvent(AiChatStreamEvent.textDelta(text));
        continue;
      }

      // Thinking / reasoning (Gemini 2.5 `thought` field).
      final thought = part['thought'];
      if (thought == true) {
        final thinkingText = '${part['text'] ?? ''}';
        if (thinkingText.isNotEmpty) {
          reasoningBuffer.write(thinkingText);
          markStreamActivity('reasoning_delta');
          emitEvent(AiChatStreamEvent.reasoningDelta(thinkingText));
          continue;
        }
      }

      // Function call (tool use).
      final functionCall = part['functionCall'];
      if (functionCall is Map<String, Object?>) {
        final name = '${functionCall['name'] ?? ''}'.trim();
        if (name.isNotEmpty) {
          final index = toolCalls.length;
          final entry = toolCalls.putIfAbsent(index, () => _MutableToolCall());
          entry.id = 'gemini-tc-$index';
          entry.name = name;
          final args = functionCall['args'];
          final argsJson = args is Map ? jsonEncode(args) : '{}';
          entry.argumentsBuffer.write(argsJson);
          markStreamActivity('tool_call_delta');
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

void _debugAiStreamLog(String message) {
  return;
}

class AiChatException implements Exception {
  const AiChatException(this.message);

  final String message;

  @override
  String toString() => message;
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
      throw AiChatException(
        'Too many redirects (${_maxAiChatRedirects + 1})${responseBody.trim().isEmpty ? '' : ': ${responseBody.trim()}'}',
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
      final itemMap = Map<String, Object?>.from(item);
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
    final itemMap = Map<String, Object?>.from(item);
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
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

_StreamingGeneratedMedia? _streamingGeneratedMediaFromUrl(
  String value, {
  String? hintedKind,
  bool allowHintedKindWithoutExtension = false,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > _maxStreamingMediaUrlChars) {
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
  final normalized = mimeType.trim().toLowerCase();
  if (normalized.startsWith('image/')) return 'image';
  if (normalized.startsWith('video/')) return 'video';
  if (normalized.startsWith('audio/')) return 'audio';
  return null;
}

String? _streamingMediaKindFromType(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('image')) return 'image';
  if (normalized.contains('video')) return 'video';
  if (normalized.contains('audio')) return 'audio';
  return null;
}

String? _streamingMediaKindFromField(String key) {
  return _streamingMediaKindFromType(key.replaceAll('_', '-'));
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

/// 集中收敛 Chat / Stream 调用阶段的错误文案。理念与
/// `AiModelScanner._ScanErrorMessages` 一致：以「现象 / 原因 / 建议」
/// 三段式中英双语呈现，避免直接抛出 BoringSSL / dart:io 内部错误码
/// 让用户摸不着头脑。所有方法返回纯文本，由 [AiChatException]
/// 包装后在 UI 层渲染。
class _ChatErrorMessages {
  _ChatErrorMessages._();

  static String handshake(HandshakeException e) {
    final detail = e.message.trim();
    return _format(
      title: 'TLS handshake rejected · TLS 握手被拒绝',
      reason:
          '请求未到达业务层，TLS 握手就被服务端 / 中间设备拒绝。常见原因：\n'
          '  · Cloudflare / WAF 通过 JA3 / JA4 指纹封锁了非浏览器 TLS 客户端\n'
          '  · 服务端要求强制 TLS 1.3，本地链路被中间盒降级\n'
          '  · 系统时间偏差过大导致证书被判定为未生效 / 已过期\n'
          '  · 客户端与服务端无可协商的加密套件',
      try_:
          '· 切换其他可访问的中转 / 直连官方 endpoint\n'
          '· 检查本机系统时间是否准确\n'
          '· 通过 curl 等工具复现，确认是否被 WAF 拦截',
      raw: detail.isEmpty ? null : detail,
    );
  }

  static String tls(TlsException e) {
    return _format(
      title: 'TLS error · TLS 协议错误',
      reason:
          'TLS 通道异常：${e.message}\n'
          '常见诱因：\n'
          '  · 服务端证书过期、域名不匹配或未由可信 CA 签发\n'
          '  · 中间存在 HTTPS 拦截 (公司防火墙 / 抓包工具)\n'
          '  · 本机根证书库过旧未包含目标 CA',
      try_: '· 在浏览器打开同一 URL 检查证书是否报警\n· 关闭抓包工具 / 公司代理后再试\n· 联系中转方确认证书链',
    );
  }

  static String socket(SocketException e) {
    final msg = e.message.toLowerCase();
    String reason;
    String suggest;
    if (msg.contains('failed host lookup') || msg.contains('no address')) {
      reason =
          '主机名 DNS 解析失败。可能的原因：\n'
          '  · Base URL 写错或多/少了协议前缀\n'
          '  · 本机 DNS 配置异常或网络无外网\n'
          '  · 域名被运营商屏蔽 / 劫持';
      suggest = '· 复核 Base URL\n· 在终端执行 `ping`/`nslookup` 验证\n· 切换网络 / VPN';
    } else if (msg.contains('connection refused')) {
      reason = 'TCP 连接被服务端主动拒绝。可能服务未启动 / 端口写错 / 防火墙拦截。';
      suggest = '· 确认 Base URL 中端口与服务端实际端口一致\n· 暂停本机防火墙再试';
    } else if (msg.contains('network is unreachable') ||
        msg.contains('no route to host')) {
      reason = '本机当前无法到达目标网络 (network unreachable / no route to host)。';
      suggest = '· 检查 Wi-Fi / 蜂窝 / 有线连接\n· 内网目标请确认 VPN 已连通';
    } else if (msg.contains('timed out') || msg.contains('timeout')) {
      reason =
          'TCP 连接超时。常见诱因：\n'
          '  · 跨境弱网 / 中间链路丢包\n'
          '  · 服务端被防火墙静默丢包\n'
          '  · 端口被运营商屏蔽';
      suggest = '· 切换网络后重试\n· traceroute / mtr 定位卡点';
    } else {
      reason = '底层 socket 抛出错误：${e.message}';
      suggest = '· 重试或更换网络环境';
    }
    return _format(
      title: 'Network error · 网络层错误',
      reason: reason,
      try_: suggest,
      raw: e.osError == null ? e.message : '${e.message} (${e.osError})',
    );
  }

  static String httpClient(http.ClientException e) {
    return _format(
      title: 'HTTP client error · HTTP 客户端错误',
      reason: 'HTTP 客户端在处理请求 / 响应阶段失败：${e.message}\n通常意味着连接中断、响应被截断、或服务端关闭连接。',
      try_: '· 稍后重试\n· 检查网络稳定性\n· 联系中转方确认服务状态',
    );
  }

  static String timeout(Duration limit) {
    return _format(
      title: 'Request timed out · 请求超时',
      reason:
          '本次调用在 ${limit.inSeconds} 秒内未能完成。常见诱因：\n'
          '  · 跨境网络延迟过高\n'
          '  · 服务端处理慢 / 队列拥塞\n'
          '  · 中间代理在传输中卡死',
      try_: '· 稍后重试\n· 切换网络或中转\n· 缩短上下文长度后再发送',
    );
  }

  static String httpStatus(int code, {String serverMessage = ''}) {
    String title;
    String reason;
    String suggest;
    switch (code) {
      case 400:
        title = 'Bad request (400) · 请求被拒';
        reason = '服务端拒绝处理本次请求 (400)。请求体可能不符合该协议规范，或附件 / 参数超出允许范围。';
        suggest = '· 复核 Base URL 与协议是否匹配\n· 缩减消息长度 / 附件数量后重试';
        break;
      case 401:
        title = 'Authentication failed (401) · 鉴权失败';
        reason = '服务端返回 401 Unauthorized：身份令牌缺失或已失效。';
        suggest = '· 确认 API Key / Token 已正确粘贴，无前后空格\n· 在中转方控制台重新生成令牌';
        break;
      case 403:
        title = 'Forbidden (403) · 访问被拒';
        reason = '服务端返回 403 Forbidden：当前令牌无权访问该模型，或 IP 不在允许地区，或触发了 WAF / 风控。';
        suggest = '· 在中转方控制台确认账号余额与权限\n· 切换网络 / VPN 后重试';
        break;
      case 404:
        title = 'Endpoint not found (404) · 端点不存在';
        reason = '服务端返回 404 Not Found：Base URL 路径错误，或所选模型在该中转尚未上架。';
        suggest = '· 复核 Base URL 与模型 ID\n· 在中转方控制台查看可用模型列表';
        break;
      case 408:
        title = 'Server timeout (408) · 服务端超时';
        reason = '服务端在收到请求头后超时关闭连接 (408)。';
        suggest = '· 稍后重试\n· 切换网络后再试';
        break;
      case 413:
        title = 'Payload too large (413) · 请求体过大';
        reason = '请求体超过中转 / 上游允许的最大尺寸 (413)。多发生于附件较多或上下文过长的场景。';
        suggest = '· 删减附件数量 / 大小\n· 缩短上下文 / 摘要旧消息后再发送';
        break;
      case 429:
        title = 'Rate limited (429) · 触发限流';
        reason = '服务端返回 429 Too Many Requests：调用过于频繁或额度已用尽。';
        suggest = '· 稍等几分钟后重试\n· 在中转方控制台确认配额 / 余额';
        break;
      case 500:
        title = 'Server error (500) · 服务端内部错误';
        reason = '服务端返回 500 Internal Server Error：上游或中转方自身出现故障。';
        suggest = '· 稍后重试\n· 联系中转方查看服务状态';
        break;
      case 502:
        title = 'Bad gateway (502) · 网关异常';
        reason = '服务端返回 502 Bad Gateway：中转无法从上游 (Anthropic / OpenAI 等) 取得有效响应。';
        suggest = '· 稍后重试\n· 联系中转方确认上游通路';
        break;
      case 503:
        title = 'Service unavailable (503) · 服务不可用';
        reason = '服务端返回 503 Service Unavailable：服务在维护或被熔断。';
        suggest = '· 稍后重试\n· 关注中转方公告';
        break;
      case 504:
        title = 'Gateway timeout (504) · 网关超时';
        reason = '服务端返回 504 Gateway Timeout：中转访问上游 LLM 时超时。';
        suggest = '· 稍后重试\n· 切换中转或缩短上下文后再试';
        break;
      default:
        if (code >= 500) {
          title = 'Server error ($code) · 服务端错误';
          reason = '服务端返回 $code，多为中转 / 上游故障。';
          suggest = '· 稍后重试\n· 联系中转方排查';
        } else if (code >= 400) {
          title = 'Client error ($code) · 客户端请求被拒';
          reason = '服务端返回 $code，请求未通过协议或鉴权校验。';
          suggest = '· 复核 Base URL / token / 自定义 header';
        } else {
          title = 'Unexpected status ($code) · 非预期响应';
          reason = '服务端返回非 2xx 状态码 $code。';
          suggest = '· 联系中转方排查';
        }
    }
    final trimmedServer = serverMessage.trim();
    return _format(
      title: title,
      reason: reason,
      try_: suggest,
      raw: trimmedServer.isEmpty ? null : trimmedServer,
    );
  }

  static String _format({
    required String title,
    required String reason,
    required String try_,
    String? raw,
  }) {
    final buf = StringBuffer()
      ..writeln(title)
      ..writeln('原因 / Why:')
      ..writeln(reason)
      ..writeln('建议 / Try:')
      ..write(try_);
    if (raw != null && raw.isNotEmpty) {
      buf
        ..writeln()
        ..write('服务端原文 / Server says: $raw');
    }
    return buf.toString();
  }
}
