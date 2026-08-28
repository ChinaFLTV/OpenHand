import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../../app/support/silent_log.dart';
import '../../../../app/support/system_proxy.dart';
import '../../../../shared/net/http_error_message.dart';
import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/net/http_response_utils.dart';
import '../../../../shared/net/http_status_utils.dart';
import '../../../../shared/net/sse_line_parsing.dart';
import '../../../../shared/ui/error_source.dart';
import '../../../../shared/ui/structured_error_text.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_api_dialect.dart';
import '../../model/ai_api_family.dart';
import '../../model/ai_creation_mode.dart';
import '../../model/ai_input_cache_runtime_config.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../../model/ai_tool_call_limit_policy.dart';
import '../dsml/ai_dsml_tool_call_parser.dart';
import '../media/ai_image_generation_service.dart';
import '../model_registry/ai_model_scanner.dart';
import '../operations/ai_responses_service.dart';
import '../runtime/ai_endpoint_router.dart';
import '../session_io/ai_token_usage_parser.dart';
import '../usage/ai_usage_tracker.dart';
import 'ai_protocol_adapter.dart';
import 'ai_transport_diagnostic_messages.dart';

const String aiChatRequestFallbackCacheAffinityRejected =
    'cache_affinity_rejected';
const String aiChatRequestFallbackCacheRetentionRejected =
    'cache_retention_rejected';
const String aiChatRequestFallbackThinkingMarkersRejected =
    'thinking_markers_rejected';
const String aiChatRequestFallbackResponsesUnsupported =
    'responses_unsupported';

final RegExp _mediaPromptHeaderPattern = RegExp(r'^#\s*\[\d+\]\s*[^\n]*\n+');

AiChatTurn? mediaGenerationInputTurn(List<AiChatTurn> messages) {
  for (final turn in messages.reversed) {
    if (turn.role != AiChatRole.user) continue;
    var prompt = turn.content.trim();
    if (prompt.isEmpty) {
      prompt = trimmedNonEmptyStrings(
        turn.effectiveParts
            .where((part) => part.kind == AiChatContentPartKind.text)
            .map((part) => part.text),
      ).join('\n');
    }
    prompt = prompt.replaceFirst(_mediaPromptHeaderPattern, '').trim();
    final referenceParts = turn.effectiveParts
        .where((part) => part.kind == AiChatContentPartKind.imageFile)
        .toList(growable: false);
    if (prompt.isEmpty && referenceParts.isEmpty) continue;
    return AiChatTurn(
      role: AiChatRole.user,
      content: prompt,
      parts: referenceParts,
    );
  }
  return null;
}

bool usesDedicatedMediaGenerationEndpoint(
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
    bool allowResponsesFallback = true,
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

  Future<AiModelTestResult> testModel(AiModelConfig model);

  void dispose();
}

class AiModelTestResult {
  const AiModelTestResult({
    required this.reply,
    required this.chatApiFamily,
    this.requestUrl,
    this.requestMethod,
    this.durationMs,
  });

  final String reply;
  final AiApiFamily chatApiFamily;
  final String? requestUrl;
  final String? requestMethod;
  final int? durationMs;
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
    this.requestFallbacks = const <String>[],
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
  final List<String> requestFallbacks;
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
    this.requestFallbacks = const <String>[],
  });

  final String reply;

  /// 支持扩展思考的模型返回的推理内容；不可用时为 null。
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
  final List<String> requestFallbacks;
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
    this.firstTokenAt,
    this.endedAt,
    this.durationMs,
    this.streamEventCount = 0,
    this.textDeltaCount = 0,
    this.reasoningDeltaCount = 0,
    this.toolCallDeltaCount = 0,
    this.requestFallbacks = const <String>[],
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
  final DateTime? firstTokenAt;
  final DateTime? endedAt;
  final int? durationMs;
  final int streamEventCount;
  final int textDeltaCount;
  final int reasoningDeltaCount;
  final int toolCallDeltaCount;
  final List<String> requestFallbacks;

  AiChatStreamResult withStreamObservability({
    required DateTime startedAt,
    required DateTime endedAt,
    required DateTime? firstTokenAt,
    required int streamEventCount,
    required int textDeltaCount,
    required int reasoningDeltaCount,
    required int toolCallDeltaCount,
  }) {
    return AiChatStreamResult(
      reply: reply,
      reasoning: reasoning,
      toolCalls: toolCalls,
      wasCancelled: wasCancelled,
      usage: usage,
      rawResponse: rawResponse,
      finishReason: finishReason,
      requestUrl: requestUrl,
      requestMethod: requestMethod,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      startedAt: startedAt,
      firstTokenAt: firstTokenAt,
      endedAt: endedAt,
      durationMs: endedAt.difference(startedAt).inMilliseconds,
      streamEventCount: streamEventCount,
      textDeltaCount: textDeltaCount,
      reasoningDeltaCount: reasoningDeltaCount,
      toolCallDeltaCount: toolCallDeltaCount,
      requestFallbacks: requestFallbacks,
    );
  }

  /// 模型停止生成的原因。
  ///
  /// 常见值：
  ///   - `'stop'` / `'end_turn'`：正常结束
  ///   - `'length'` / `'max_tokens'`：达到令牌上限而截断
  ///   - `'tool_calls'` / `'tool_use'`：模型请求执行工具
  ///   - `null`：未知或服务端未返回
  final String? finishReason;

  /// 模型输出是否因达到最大输出令牌数而截断。
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

  /// 用户在建流阶段取消：不产生任何事件，直接给出已取消的空结果。
  ///
  /// 两条流式链路（messages / responses）的每一级降级重试都要用它，此前
  /// 在同一文件里逐字重复了 8 次。
  factory AiChatStreamingResponse.cancelled() {
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
       _ownsClient = client == null,
       _imageService = imageService ?? AiImageGenerationService(client: client),
       _ownsImageService = imageService == null,
       _modelScanner = modelScanner;

  static const String _availabilityProbePrompt =
      'Reply with OK only if this model configuration works.';
  static const int _maxConcurrentRequests = 16;
  static const int _maxQueuedRequests = 128;
  static const Duration _requestQueueTimeout = Duration(seconds: 30);

  /// SSE 单事件缓冲上限；超限立即终止响应，避免异常服务持续占用资源。
  int _maxStreamLineBufferBytes = 4 * kBytesPerMiB;
  int get maxStreamLineBufferBytes => _maxStreamLineBufferBytes;
  set maxStreamLineBufferBytes(int value) {
    _maxStreamLineBufferBytes = value.clamp(
      1,
      _maxRetainedStreamResponseCharacters,
    );
  }

  final http.Client _client;
  final bool _ownsClient;
  final AiImageGenerationService _imageService;
  final bool _ownsImageService;
  final AiModelScanner? _modelScanner;
  final OpenHandAsyncSemaphore _requestSlots = OpenHandAsyncSemaphore(
    _maxConcurrentRequests,
    maxWaiters: _maxQueuedRequests,
  );
  final Set<Completer<void>> _activeRequestAborts = <Completer<void>>{};
  AiResponsesService? _responsesService;
  bool _disposed = false;
  static const AiEndpointRouter _endpointRouter = AiEndpointRouter();
  static const Duration _responsesCompatibilityCacheTtl = Duration(minutes: 10);
  static const int _responsesCompatibilityCacheMaxEntries = 64;
  final Stopwatch _responsesCompatibilityStopwatch = Stopwatch()..start();
  final Map<String, Duration> _unsupportedResponsesEndpoints =
      <String, Duration>{};
  final Map<String, Duration> _unsupportedResponsesRequestShapes =
      <String, Duration>{};

  bool _canUseResponsesFamily({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    required List<AiToolDefinition> tools,
    required List<String> responseModalities,
    required AiCreationRequest creationRequest,
  }) {
    final capabilityStatus = lowercaseStringFromValue(
      model.capabilityStatusFor(AiApiFamily.responses),
    );
    if (model.apiDialect != AiApiDialect.openAiCompat ||
        creationRequest.mode == AiCreationMode.video ||
        creationRequest.mode == AiCreationMode.audio ||
        capabilityStatus == 'disabled') {
      return false;
    }
    if (model.protocolType == AiProtocolType.mimo &&
        messages.any(
          (turn) => turn.effectiveParts.any(
            (part) =>
                part.kind == AiChatContentPartKind.videoFile ||
                part.kind == AiChatContentPartKind.audioFile,
          ),
        )) {
      return false;
    }
    if (capabilityStatus == 'supported') return true;
    final endpointKey = _responsesEndpointKey(model);
    if (_hasFreshResponsesCompatibilityEntry(
      _unsupportedResponsesEndpoints,
      endpointKey,
    )) {
      return false;
    }
    return !_hasFreshResponsesCompatibilityEntry(
      _unsupportedResponsesRequestShapes,
      _responsesRequestShapeKey(
        endpointKey: endpointKey,
        modelId: model.resolveOperationModelId(AiApiFamily.responses),
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        creationRequest: creationRequest,
      ),
    );
  }

  bool _hasFreshResponsesCompatibilityEntry(
    Map<String, Duration> cache,
    String key,
  ) {
    final expiresAt = cache[key];
    if (expiresAt == null) return false;
    if (expiresAt > _responsesCompatibilityStopwatch.elapsed) return true;
    cache.remove(key);
    return false;
  }

  void _cacheResponsesIncompatibility(Map<String, Duration> cache, String key) {
    final now = _responsesCompatibilityStopwatch.elapsed;
    cache.removeWhere((_, expiresAt) => expiresAt <= now);
    cache.remove(key);
    while (cache.length >= _responsesCompatibilityCacheMaxEntries) {
      cache.remove(cache.keys.first);
    }
    cache[key] = now + _responsesCompatibilityCacheTtl;
  }

  String _responsesEndpointKey(AiModelConfig model) {
    final endpoint = _endpointRouter.resolve(model, AiApiFamily.responses).url;
    return '${model.id}|$endpoint';
  }

  String _responsesRequestShapeKey({
    required String endpointKey,
    required String modelId,
    required List<AiChatTurn> messages,
    required List<AiToolDefinition> tools,
    required List<String> responseModalities,
    required AiCreationRequest creationRequest,
  }) {
    final hasImages = messages.any(
      (turn) => turn.effectiveParts.any(
        (part) => part.kind == AiChatContentPartKind.imageFile,
      ),
    );
    final hasVideos = messages.any(
      (turn) => turn.effectiveParts.any(
        (part) => part.kind == AiChatContentPartKind.videoFile,
      ),
    );
    final hasAudio = messages.any(
      (turn) => turn.effectiveParts.any(
        (part) => part.kind == AiChatContentPartKind.audioFile,
      ),
    );
    final hasToolHistory = messages.any(
      (turn) => turn.role == AiChatRole.tool || turn.toolCalls.isNotEmpty,
    );
    final modalities = responseModalities.toSet().toList(growable: false)
      ..sort();
    return '$endpointKey|model:$modelId'
        '|tools:${tools.isNotEmpty || hasToolHistory}'
        '|images:$hasImages|videos:$hasVideos|audio:$hasAudio'
        '|creation:${creationRequest.mode.storageValue}'
        '|modalities:${modalities.join(',')}';
  }

  void _rememberResponsesIncompatibility({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    required List<AiToolDefinition> tools,
    required List<String> responseModalities,
    required AiCreationRequest creationRequest,
    required AiResponsesHttpException error,
  }) {
    final endpointKey = _responsesEndpointKey(model);
    if (error.isEndpointIncompatible) {
      _cacheResponsesIncompatibility(
        _unsupportedResponsesEndpoints,
        endpointKey,
      );
      return;
    }
    _cacheResponsesIncompatibility(
      _unsupportedResponsesRequestShapes,
      _responsesRequestShapeKey(
        endpointKey: endpointKey,
        modelId: model.resolveOperationModelId(AiApiFamily.responses),
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        creationRequest: creationRequest,
      ),
    );
  }

  String _effectiveRequestMethod(AiModelConfig model) =>
      nullIfBlank(model.requestMethod) ?? 'POST';

  AiChatException _chatExceptionFromResponses(AiResponsesHttpException error) {
    return AiChatException(
      error.message,
      statusCode: error.statusCode,
      telemetry: AiChatRequestTelemetry(
        requestUrl: error.request.url,
        requestMethod: error.request.method,
        requestHeaders: error.request.headers,
        requestBody: error.request.body,
        rawResponse: error.body,
        startedAt: error.startedAt,
        endedAt: error.endedAt,
        durationMs: error.endedAt.difference(error.startedAt).inMilliseconds,
        error: error.message,
        requestFallbacks: error.requestFallbacks,
      ),
    );
  }

  AiChatException _chatExceptionFromResponsesPayload(
    AiResponsesPayloadException error,
  ) {
    final request = error.request;
    final startedAt = error.startedAt;
    final endedAt = error.endedAt;
    return AiChatException(
      error.message,
      telemetry: request == null
          ? null
          : AiChatRequestTelemetry(
              requestUrl: request.url,
              requestMethod: request.method,
              requestHeaders: request.headers,
              requestBody: request.body,
              rawResponse: error.body,
              startedAt: startedAt,
              endedAt: endedAt,
              durationMs: startedAt == null || endedAt == null
                  ? null
                  : endedAt.difference(startedAt).inMilliseconds,
              error: error.message,
              requestFallbacks: error.requestFallbacks,
            ),
    );
  }

  AiChatException _imageResponsesUnavailable(AiModelConfig model) {
    return AiChatException(
      '当前模型 "${model.modelId}" 的 Responses 图片工具不可用，且未配置兼容的专用图片生成端点。',
    );
  }

  void _addRequestFallback(List<String> fallbacks, String reason) {
    if (reason.isEmpty || fallbacks.contains(reason)) {
      return;
    }
    fallbacks.add(reason);
  }

  AiRequestBlueprint _withoutCacheAffinityMarkers(
    AiRequestBlueprint blueprint,
  ) {
    return blueprint.copyWith(
      headers: AiPromptCacheAffinity.withoutHeaderMarkers(blueprint.headers),
      body: AiPromptCacheAffinity.withoutBodyMarkers(blueprint.body),
    );
  }

  AiRequestBlueprint _withoutCacheRetentionMarker(
    AiRequestBlueprint blueprint,
  ) {
    return blueprint.copyWith(
      body: AiPromptCacheRetentionPolicy.withoutMarker(blueprint.body),
    );
  }

  AiRequestBlueprint _withoutThinkingMarkers(AiRequestBlueprint blueprint) {
    return blueprint.copyWith(
      body: AiThinkingRequestPolicy.withoutRequestMarkers(blueprint.body),
    );
  }

  /// 请求视频或音频但模型不支持时，提前返回明确错误，避免误入聊天端点。
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
      case AiCreationMode.audio:
        if (!AiImageGenerationService.supportsAudioGenerationForModel(model)) {
          throw AiChatException(
            '当前模型 "${model.modelId}" 不具备音频生成能力，请切换到具备音频生成能力的模型后再试。',
          );
        }
      case AiCreationMode.image:
      case AiCreationMode.none:
      case AiCreationMode.deepResearch:
        break;
    }
  }

  /// 调用专用媒体端点，并将结果统一封装为聊天完成结构。
  Future<AiChatCompletion> _sendMediaGenerationCompletion({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    required AiCreationRequest creationRequest,
    required Duration timeout,
    List<String> requestFallbacks = const <String>[],
    Future<void>? cancelSignal,
  }) async {
    final inputTurn = mediaGenerationInputTurn(messages);
    final prompt = inputTurn?.content ?? '';
    final referenceImages = inputTurn?.parts ?? const <AiChatContentPart>[];
    final AiMediaGenerationResult result;
    try {
      result = switch (creationRequest.mode) {
        AiCreationMode.image => await _imageService.generateImage(
          model: model,
          prompt: prompt,
          options: creationRequest.options,
          referenceImages: referenceImages,
          timeout: timeout,
          cancelSignal: cancelSignal,
        ),
        AiCreationMode.video => await _imageService.generateVideo(
          model: model,
          prompt: prompt,
          options: creationRequest.options,
          referenceImages: referenceImages,
          timeout: timeout,
          cancelSignal: cancelSignal,
        ),
        AiCreationMode.audio => await _imageService.generateAudio(
          model: model,
          prompt: prompt,
          options: creationRequest.options,
          timeout: timeout,
          cancelSignal: cancelSignal,
        ),
        AiCreationMode.none || AiCreationMode.deepResearch =>
          throw const AiMediaGenerationException('未指定媒体生成模式。'),
      };
    } on AiMediaGenerationCancelledException {
      throw const AiChatCancelledException();
    } on http.RequestAbortedException {
      throw const AiChatCancelledException();
    }
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
      requestFallbacks: List<String>.unmodifiable(requestFallbacks),
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
    bool allowResponsesFallback = true,
  }) async {
    final requestAbort = await _beginRequest(cancelSignal);
    final effectiveCancelSignal = combineCancelSignals(<Future<void>?>[
      cancelSignal,
      requestAbort.future,
    ])!;
    final startedAt = DateTime.now().toUtc();
    try {
      final completion = await _sendMessage(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        creationRequest: creationRequest,
        timeout: timeout,
        cancelSignal: effectiveCancelSignal,
        inputCacheConfig: inputCacheConfig,
        onRequestStarted: onRequestStarted,
        allowResponsesFallback: allowResponsesFallback,
      );
      final endedAt = DateTime.now().toUtc();
      AiUsageTracker.instance.recordSuccess(
        model: model,
        apiFamily: _usageApiFamily(
          model: model,
          messages: messages,
          tools: tools,
          responseModalities: responseModalities,
          request: creationRequest,
          requestFallbacks: completion.requestFallbacks,
        ),
        startedAt: startedAt,
        endedAt: endedAt,
        inputCharacters: _requestCharacterCount(
          messages,
          tools,
          model: model,
          creationRequest: creationRequest,
        ),
        outputCharacters: _completionCharacterCount(
          completion,
          model: model,
          creationRequest: creationRequest,
        ),
        usage: completion.usage,
        metadata: <String, Object?>{
          'streaming': false,
          'request_fallback_count': completion.requestFallbacks.length,
          ..._usageRequestMetadata(
            completion.requestUrl,
            completion.requestMethod,
            completion.requestHeaders,
          ),
        },
      );
      return completion;
    } catch (error) {
      AiUsageTracker.instance.recordFailure(
        model: model,
        apiFamily: _usageApiFamily(
          model: model,
          messages: messages,
          tools: tools,
          responseModalities: responseModalities,
          request: creationRequest,
          requestFallbacks: _requestFallbacksFromError(error),
        ),
        startedAt: startedAt,
        endedAt: DateTime.now().toUtc(),
        error: error,
        timeout: timeout,
        cancelled:
            error is AiChatCancelledException ||
            error is http.RequestAbortedException,
        metadata: <String, Object?>{
          'streaming': false,
          ..._usageErrorMetadata(error),
        },
      );
      rethrow;
    } finally {
      _finishRequest(requestAbort);
    }
  }

  Future<AiChatCompletion> _sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 60),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
    bool allowResponsesFallback = true,
  }) async {
    _assertCreationModeIsRoutable(model, creationRequest);
    final canUseResponses = _canUseResponsesFamily(
      model: model,
      messages: messages,
      tools: tools,
      responseModalities: responseModalities,
      creationRequest: creationRequest,
    );
    final routeFallbacks = <String>[];
    if (canUseResponses) {
      try {
        _responsesService ??= AiResponsesService(client: _client);
        final response = await _awaitWithCancelSignal(
          _responsesService!.createChatResponse(
            model: model,
            messages: messages,
            tools: tools,
            imageGenerationOptions: creationRequest.mode == AiCreationMode.image
                ? creationRequest.options
                : null,
            timeout: timeout,
            inputCacheConfig: inputCacheConfig,
            cancelSignal: cancelSignal,
            onRequestStarted: (request) {
              onRequestStarted?.call(
                AiChatRequestTelemetry(
                  requestUrl: request.url,
                  requestMethod: request.method,
                  requestHeaders: request.headers,
                  requestBody: request.body,
                  startedAt: DateTime.now().toUtc(),
                ),
              );
            },
          ),
          cancelSignal,
        );
        final dsmlExtraction = extractDsmlToolCalls(response.text);
        return AiChatCompletion(
          reply: dsmlExtraction.sanitizedText,
          reasoningContent: response.reasoning,
          usage: response.usage,
          rawResponse: response.rawResponse,
          toolCalls: response.toolCalls.isNotEmpty
              ? response.toolCalls
              : dsmlExtraction.toolCalls,
          requestUrl: response.requestUrl,
          requestMethod: response.requestMethod,
          requestHeaders: response.requestHeaders,
          requestBody: response.requestBody,
          startedAt: response.startedAt,
          endedAt: response.endedAt,
          durationMs: response.durationMs,
          requestFallbacks: <String>[
            ...routeFallbacks,
            ...response.requestFallbacks,
          ],
        );
      } on AiChatCancelledException {
        rethrow;
      } on AiResponsesHttpException catch (error) {
        if (!allowResponsesFallback || !error.isCompatibilityFailure) {
          throw _chatExceptionFromResponses(error);
        }
        _rememberResponsesIncompatibility(
          model: model,
          messages: messages,
          tools: tools,
          responseModalities: responseModalities,
          creationRequest: creationRequest,
          error: error,
        );
        for (final reason in error.requestFallbacks) {
          _addRequestFallback(routeFallbacks, reason);
        }
        _addRequestFallback(
          routeFallbacks,
          aiChatRequestFallbackResponsesUnsupported,
        );
      } on AiResponsesPayloadException catch (error) {
        throw _chatExceptionFromResponsesPayload(error);
      }
    }
    if (usesDedicatedMediaGenerationEndpoint(model, creationRequest)) {
      try {
        return await _awaitWithCancelSignal(
          _sendMediaGenerationCompletion(
            model: model,
            messages: messages,
            creationRequest: creationRequest,
            timeout: timeout,
            requestFallbacks: routeFallbacks,
            cancelSignal: cancelSignal,
          ),
          cancelSignal,
        );
      } on AiMediaGenerationException catch (error) {
        throw AiChatException(error.message);
      }
    }
    if (creationRequest.mode == AiCreationMode.image &&
        model.apiDialect == AiApiDialect.openAiCompat) {
      throw _imageResponsesUnavailable(model);
    }
    try {
      final adapter = AiProtocolRegistry.adapterForModel(model);
      var blueprint = await adapter.buildChatRequest(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        inputCacheConfig: inputCacheConfig,
      );
      if (AiPromptCacheRetentionPolicy.wasRecentlyRejected(
        requestUrl: blueprint.url,
        requestBody: blueprint.body,
      )) {
        blueprint = _withoutCacheRetentionMarker(blueprint);
      }
      final effectiveMethod = _effectiveRequestMethod(model);
      final startedAt = DateTime.now().toUtc();
      final requestFallbacks = <String>[...routeFallbacks];
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
          requestFallbacks: List<String>.unmodifiable(requestFallbacks),
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
            requestFallbacks: List<String>.unmodifiable(requestFallbacks),
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
              cancelSignal: cancelSignal,
            ).then(
              (response) =>
                  _collectBoundedChatHttpResponse(response, timeout: timeout),
            ),
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
      if (isHttpFailureStatus(response.statusCode) &&
          AiPromptCacheRetentionPolicy.shouldRetryWithoutMarker(
            statusCode: response.statusCode,
            errorBody: response.body,
            requestBody: blueprint.body,
          )) {
        AiPromptCacheRetentionPolicy.rememberRejection(
          requestUrl: blueprint.url,
          requestBody: blueprint.body,
        );
        _addRequestFallback(
          requestFallbacks,
          aiChatRequestFallbackCacheRetentionRejected,
        );
        response = await sendBlueprint(_withoutCacheRetentionMarker(blueprint));
        endedAt = DateTime.now().toUtc();
      }
      if (isHttpFailureStatus(response.statusCode)) {
        if (AiPromptCacheAffinity.shouldRetryWithoutMarkers(
          statusCode: response.statusCode,
          errorBody: response.body,
          requestBody: blueprint.body,
          requestHeaders: blueprint.headers,
        )) {
          _addRequestFallback(
            requestFallbacks,
            aiChatRequestFallbackCacheAffinityRejected,
          );
          response = await sendBlueprint(
            _withoutCacheAffinityMarkers(blueprint),
          );
          endedAt = DateTime.now().toUtc();
        }
      }
      if (isHttpFailureStatus(response.statusCode)) {
        if (AiThinkingRequestPolicy.shouldRetryWithoutMarkers(
          statusCode: response.statusCode,
          errorBody: response.body,
          requestBody: blueprint.body,
        )) {
          _addRequestFallback(
            requestFallbacks,
            aiChatRequestFallbackThinkingMarkersRejected,
          );
          response = await sendBlueprint(_withoutThinkingMarkers(blueprint));
          endedAt = DateTime.now().toUtc();
        }
      }
      if (isHttpFailureStatus(response.statusCode)) {
        final errorMessage = adapter.extractErrorMessage(response.body);
        final message = AiTransportDiagnosticMessages.httpStatus(
          response.statusCode,
          serverMessage: errorMessage,
        );
        throw AiChatException(
          message,
          statusCode: response.statusCode,
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
        // 单独提取推理模型专用字段中的思考内容。
        final reasoningText = _extractReasoningContent(response.body);
        // 正文为空时解析器会用推理内容兜底，此处去重以免 UI 重复展示。
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
          requestFallbacks: List<String>.unmodifiable(requestFallbacks),
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

  /// 从 OpenAI 兼容响应中提取 `reasoning_content`，缺失或为空时返回 null。
  static String? _extractReasoningContent(String rawResponse) {
    try {
      final decoded = jsonDecode(rawResponse);
      if (decoded is! Map<String, Object?>) return null;
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        final message = first is Map ? first['message'] : null;
        if (message is Map) {
          final reasoning =
              message['reasoning_content'] ?? message['reasoning'];
          if (reasoning is String) return nullIfBlank(reasoning);
        }
      }
      final content = decoded['content'];
      if (content is List) {
        final reasoning = content
            .whereType<Map>()
            .where(
              (block) => lowercaseStringFromValue(block['type']) == 'thinking',
            )
            .map(
              (block) =>
                  optionalStringFromValue(block['thinking']) ??
                  optionalStringFromValue(block['text']),
            )
            .whereType<String>()
            .join('\n');
        return nullIfBlank(reasoning);
      }
    } catch (error, stack) {
      silentLog('ai_chat_service', '提取 reasoning_content', error, stack);
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
    final requestAbort = await _beginRequest(cancelSignal);
    final effectiveCancelSignal = combineCancelSignals(<Future<void>?>[
      cancelSignal,
      requestAbort.future,
    ])!;
    final startedAt = DateTime.now().toUtc();
    AiChatStreamingResponse response;
    try {
      response = await _sendMessageStream(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        creationRequest: creationRequest,
        timeout: timeout,
        streamIdleTimeout: streamIdleTimeout,
        cancelSignal: effectiveCancelSignal,
        inputCacheConfig: inputCacheConfig,
        onRequestStarted: onRequestStarted,
      );
    } catch (error) {
      AiUsageTracker.instance.recordFailure(
        model: model,
        apiFamily: _usageApiFamily(
          model: model,
          messages: messages,
          tools: tools,
          responseModalities: responseModalities,
          request: creationRequest,
          requestFallbacks: _requestFallbacksFromError(error),
        ),
        startedAt: startedAt,
        endedAt: DateTime.now().toUtc(),
        error: error,
        timeout: timeout,
        cancelled:
            error is AiChatCancelledException ||
            error is http.RequestAbortedException,
        metadata: <String, Object?>{
          'streaming': true,
          ..._usageErrorMetadata(error),
        },
      );
      _finishRequest(requestAbort);
      rethrow;
    }
    DateTime? firstTokenAt;
    var streamEventCount = 0;
    var textDeltaCount = 0;
    var reasoningDeltaCount = 0;
    var toolCallDeltaCount = 0;
    final events = response.events.map((event) {
      final hasOutput = switch (event.type) {
        AiChatStreamEventType.textDelta => event.textDelta?.isNotEmpty == true,
        AiChatStreamEventType.reasoningDelta =>
          event.reasoningDelta?.isNotEmpty == true,
        AiChatStreamEventType.toolCallDelta => event.toolCallDelta != null,
        AiChatStreamEventType.usage => false,
      };
      if (hasOutput) {
        firstTokenAt ??= DateTime.now().toUtc();
        streamEventCount += 1;
        switch (event.type) {
          case AiChatStreamEventType.textDelta:
            textDeltaCount += 1;
          case AiChatStreamEventType.reasoningDelta:
            reasoningDeltaCount += 1;
          case AiChatStreamEventType.toolCallDelta:
            toolCallDeltaCount += 1;
          case AiChatStreamEventType.usage:
            break;
        }
      }
      return event;
    });
    final result = response.result.then<AiChatStreamResult>(
      (value) {
        final endedAt = DateTime.now().toUtc();
        final observedValue = value.withStreamObservability(
          startedAt: startedAt,
          endedAt: endedAt,
          firstTokenAt: firstTokenAt,
          streamEventCount: streamEventCount,
          textDeltaCount: textDeltaCount,
          reasoningDeltaCount: reasoningDeltaCount,
          toolCallDeltaCount: toolCallDeltaCount,
        );
        if (observedValue.wasCancelled) {
          AiUsageTracker.instance.recordFailure(
            model: model,
            apiFamily: _usageApiFamily(
              model: model,
              messages: messages,
              tools: tools,
              responseModalities: responseModalities,
              request: creationRequest,
              requestFallbacks: observedValue.requestFallbacks,
            ),
            startedAt: startedAt,
            endedAt: endedAt,
            error: StateError('流式请求已取消'),
            cancelled: true,
            metadata: <String, Object?>{
              'streaming': true,
              ..._usageRequestMetadata(
                observedValue.requestUrl,
                observedValue.requestMethod,
                observedValue.requestHeaders,
              ),
            },
          );
        } else {
          AiUsageTracker.instance.recordSuccess(
            model: model,
            apiFamily: _usageApiFamily(
              model: model,
              messages: messages,
              tools: tools,
              responseModalities: responseModalities,
              request: creationRequest,
              requestFallbacks: observedValue.requestFallbacks,
            ),
            startedAt: startedAt,
            endedAt: endedAt,
            firstTokenMs: firstTokenAt?.difference(startedAt).inMilliseconds,
            inputCharacters: _requestCharacterCount(
              messages,
              tools,
              model: model,
              creationRequest: creationRequest,
            ),
            outputCharacters: _streamResultCharacterCount(
              observedValue,
              model: model,
              creationRequest: creationRequest,
            ),
            usage: observedValue.usage,
            metadata: <String, Object?>{
              'streaming': true,
              'finish_reason': observedValue.finishReason,
              'request_fallback_count': observedValue.requestFallbacks.length,
              'stream_event_count': observedValue.streamEventCount,
              ..._usageRequestMetadata(
                observedValue.requestUrl,
                observedValue.requestMethod,
                observedValue.requestHeaders,
              ),
            },
          );
        }
        return observedValue;
      },
      onError: (Object error, StackTrace stack) {
        AiUsageTracker.instance.recordFailure(
          model: model,
          apiFamily: _usageApiFamily(
            model: model,
            messages: messages,
            tools: tools,
            responseModalities: responseModalities,
            request: creationRequest,
            requestFallbacks: _requestFallbacksFromError(error),
          ),
          startedAt: startedAt,
          endedAt: DateTime.now().toUtc(),
          error: error,
          timeout: streamIdleTimeout,
          cancelled:
              error is AiChatCancelledException ||
              error is http.RequestAbortedException,
          metadata: <String, Object?>{
            'streaming': true,
            ..._usageErrorMetadata(error),
          },
        );
        Error.throwWithStackTrace(error, stack);
      },
    );
    unawaited(
      result.then<void>(
        (_) => _finishRequest(requestAbort),
        onError: (Object _, StackTrace _) => _finishRequest(requestAbort),
      ),
    );
    return AiChatStreamingResponse(
      events: events,
      result: result,
      cancel: response.cancel,
    );
  }

  Future<AiChatStreamingResponse> _sendMessageStream({
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
    final streamCancellationTimeout = _boundedStreamCancellationTimeout(
      streamIdleTimeout,
    );
    _assertCreationModeIsRoutable(model, creationRequest);
    final canUseResponses = _canUseResponsesFamily(
      model: model,
      messages: messages,
      tools: tools,
      responseModalities: responseModalities,
      creationRequest: creationRequest,
    );
    final routeFallbacks = <String>[];
    if (canUseResponses && creationRequest.mode == AiCreationMode.image) {
      // Responses 图片包含大体积 base64 数据，改用合成流避免占满 SSE 缓冲。
      return _sendMessageAsSyntheticStream(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        creationRequest: creationRequest,
        timeout: timeout,
        cancelSignal: cancelSignal,
        onRequestStarted: onRequestStarted,
        inputCacheConfig: inputCacheConfig,
        routeThroughChatRouting: true,
      );
    }
    if (canUseResponses) {
      try {
        final response = await _sendResponsesStream(
          model: model,
          messages: messages,
          tools: tools,
          creationRequest: creationRequest,
          timeout: timeout,
          streamIdleTimeout: streamIdleTimeout,
          cancelSignal: cancelSignal,
          onRequestStarted: onRequestStarted,
          inputCacheConfig: inputCacheConfig,
        );
        return response;
      } on AiResponsesHttpException catch (error) {
        if (!error.isCompatibilityFailure) {
          throw _chatExceptionFromResponses(error);
        }
        _rememberResponsesIncompatibility(
          model: model,
          messages: messages,
          tools: tools,
          responseModalities: responseModalities,
          creationRequest: creationRequest,
          error: error,
        );
        for (final reason in error.requestFallbacks) {
          _addRequestFallback(routeFallbacks, reason);
        }
        _addRequestFallback(
          routeFallbacks,
          aiChatRequestFallbackResponsesUnsupported,
        );
      }
    }
    // 专用媒体端点使用单次请求或有限轮询，以合成流统一返回最终媒体引用。
    if (usesDedicatedMediaGenerationEndpoint(model, creationRequest)) {
      return _sendMessageAsSyntheticStream(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        creationRequest: creationRequest,
        timeout: timeout,
        cancelSignal: cancelSignal,
        onRequestStarted: onRequestStarted,
        inputCacheConfig: inputCacheConfig,
        initialRequestFallbacks: routeFallbacks,
      );
    }
    if (creationRequest.mode == AiCreationMode.image &&
        model.apiDialect == AiApiDialect.openAiCompat) {
      throw _imageResponsesUnavailable(model);
    }
    final adapter = AiProtocolRegistry.adapterForModel(model);
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
        inputCacheConfig: inputCacheConfig,
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
    if (AiPromptCacheRetentionPolicy.wasRecentlyRejected(
      requestUrl: blueprint.url,
      requestBody: blueprint.body,
    )) {
      blueprint = _withoutCacheRetentionMarker(blueprint);
    }
    final effectiveMethod = _effectiveRequestMethod(model);
    final requestFallbacks = <String>[...routeFallbacks];
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
        requestFallbacks: List<String>.unmodifiable(requestFallbacks),
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
          requestFallbacks: List<String>.unmodifiable(requestFallbacks),
        ),
      );
      final streamedResponseFuture = _sendHttpRequestWithRedirects(
        client: _client,
        method: effectiveMethod,
        uri: Uri.parse(blueprint.url),
        headers: blueprint.headers,
        body: jsonEncode(blueprint.body),
        timeout: timeout,
        cancelSignal: cancelSignal,
      );
      try {
        if (cancelSignal == null) {
          return await streamedResponseFuture;
        }
        final firstResult = await Future.any<Object?>(<Future<Object?>>[
          streamedResponseFuture,
          _cancelSignalSentinel(cancelSignal, _cancelledStreamSentinel),
        ]);
        if (!identical(firstResult, _cancelledStreamSentinel)) {
          return firstResult as http.StreamedResponse;
        }
        unawaited(
          streamedResponseFuture
              .then(
                (response) => _cancelLateStreamedResponse(
                  response,
                  timeout: streamCancellationTimeout,
                ),
              )
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
      return AiChatStreamingResponse.cancelled();
    }
    if (isHttpFailureStatus(streamedResponse.statusCode)) {
      final initialErrorBody = await _readChatHttpErrorBody(
        streamedResponse,
        timeout: streamIdleTimeout,
      );
      var finalErrorBody = initialErrorBody;
      if (AiPromptCacheRetentionPolicy.shouldRetryWithoutMarker(
        statusCode: streamedResponse.statusCode,
        errorBody: finalErrorBody,
        requestBody: blueprint.body,
      )) {
        AiPromptCacheRetentionPolicy.rememberRejection(
          requestUrl: blueprint.url,
          requestBody: blueprint.body,
        );
        _addRequestFallback(
          requestFallbacks,
          aiChatRequestFallbackCacheRetentionRejected,
        );
        streamedResponse = await openStream(
          _withoutCacheRetentionMarker(blueprint),
        );
        if (streamedResponse == null) {
          return AiChatStreamingResponse.cancelled();
        }
        if (isHttpFailureStatus(streamedResponse.statusCode)) {
          finalErrorBody = await _readChatHttpErrorBody(
            streamedResponse,
            timeout: streamIdleTimeout,
          );
        }
      }
      if (isHttpFailureStatus(streamedResponse.statusCode) &&
          AiPromptCacheAffinity.shouldRetryWithoutMarkers(
            statusCode: streamedResponse.statusCode,
            errorBody: finalErrorBody,
            requestBody: blueprint.body,
            requestHeaders: blueprint.headers,
          )) {
        _addRequestFallback(
          requestFallbacks,
          aiChatRequestFallbackCacheAffinityRejected,
        );
        streamedResponse = await openStream(
          _withoutCacheAffinityMarkers(blueprint),
        );
        if (streamedResponse == null) {
          return AiChatStreamingResponse.cancelled();
        }
        if (isHttpFailureStatus(streamedResponse.statusCode)) {
          finalErrorBody = await _readChatHttpErrorBody(
            streamedResponse,
            timeout: streamIdleTimeout,
          );
        }
      }
      if (isHttpFailureStatus(streamedResponse.statusCode) &&
          AiThinkingRequestPolicy.shouldRetryWithoutMarkers(
            statusCode: streamedResponse.statusCode,
            errorBody: finalErrorBody,
            requestBody: blueprint.body,
          )) {
        _addRequestFallback(
          requestFallbacks,
          aiChatRequestFallbackThinkingMarkersRejected,
        );
        streamedResponse = await openStream(_withoutThinkingMarkers(blueprint));
        if (streamedResponse == null) {
          return AiChatStreamingResponse.cancelled();
        }
        if (isHttpFailureStatus(streamedResponse.statusCode)) {
          finalErrorBody = await _readChatHttpErrorBody(
            streamedResponse,
            timeout: streamIdleTimeout,
          );
        }
      }
      if (isHttpSuccessStatus(streamedResponse.statusCode)) {
        // 重试成功，继续读取 SSE。
      } else {
        final errorMessage = adapter.extractErrorMessage(finalErrorBody);
        final message = AiTransportDiagnosticMessages.httpStatus(
          streamedResponse.statusCode,
          serverMessage: errorMessage,
        );
        throw AiChatException(
          message,
          statusCode: streamedResponse.statusCode,
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
    final citations = <String, String>{};
    AiTokenUsage? usage;
    String? finishReason;
    String? providerWarning;
    final lineBuffer = _SseLineCarry();
    StreamSubscription<String>? responseSubscription;
    Future<void>? responseSubscriptionCancelFuture;

    Future<void> cancelResponseStream() {
      final subscription = responseSubscription;
      if (subscription == null) return Future<void>.value();
      return responseSubscriptionCancelFuture ??= _cancelStreamSubscription(
        subscription,
        timeout: streamCancellationTimeout,
        logContext: '取消聊天响应流',
      );
    }

    bool canEmitEvents() {
      return !resultCompleter.isCompleted && !eventController.isClosed;
    }

    void emitEvent(AiChatStreamEvent event) {
      if (!canEmitEvents()) {
        return;
      }
      eventController.add(event);
    }

    void failStream(String message) {
      if (resultCompleter.isCompleted) return;
      resultCompleter.completeError(
        AiChatException(
          message,
          telemetry: telemetrySnapshot(
            rawResponse: rawResponseBuffer.toString(),
            finishReason: finishReason,
            error: message,
          ),
        ),
        StackTrace.current,
      );
      if (!eventController.isClosed) {
        unawaited(eventController.close());
      }
      unawaited(cancelResponseStream());
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
      if (citations.isNotEmpty) {
        final prefix = textBuffer.isEmpty ? '' : '\n\n';
        final sources = <String>[
          '$prefix### 来源',
          ...citations.entries.map(
            (entry) => '- [${entry.value}](${entry.key})',
          ),
        ].join('\n');
        textBuffer.write(sources);
        emitEvent(AiChatStreamEvent.textDelta(sources));
      }
      if (providerWarning != null) {
        final warning =
            '${textBuffer.isEmpty ? '' : '\n\n'}> 联网搜索提示：$providerWarning';
        textBuffer.write(warning);
        emitEvent(AiChatStreamEvent.textDelta(warning));
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
      final effectiveToolCalls = resolvedParsedToolCalls.isNotEmpty
          ? resolvedParsedToolCalls
          : dsmlExtraction.toolCalls;
      if (effectiveToolCalls.length > _maxRetainedStreamToolCalls) {
        toolCalls.clear();
        failStream('AI 响应中的工具调用数量超过安全上限。');
        return;
      }
      // 服务端未返回结束原因时，用未闭合的 DSML 标记判定输出已截断。
      final effectiveFinishReason =
          dsmlExtraction.hasTrailingIncompleteMarkup && finishReason == null
          ? 'length'
          : finishReason;

      resultCompleter.complete(
        AiChatStreamResult(
          reply: dsmlExtraction.sanitizedText,
          reasoning: reasoningBuffer.toString().trim(),
          toolCalls: effectiveToolCalls,
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
          requestFallbacks: List<String>.unmodifiable(requestFallbacks),
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
        unawaited(cancelResponseStream());
        return;
      }
      if (!_tryAppendRawStreamEvent(rawResponseBuffer, data)) {
        failStream('AI 响应流超过累计保留上限。');
        return;
      }
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
      if (model.protocolType == AiProtocolType.mimo) {
        providerWarning ??= _mimoWebSearchWarningFromPayload(decoded);
      }

      // 部分兼容服务会在成功的 SSE 响应中返回错误对象。
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
                'API 错误：$errorMessage',
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
          unawaited(cancelResponseStream());
          return;
        }
      }
      final providerError = _providerStreamErrorMessage(decoded);
      if (providerError != null) {
        resultCompleter.completeError(
          AiChatException(
            providerError,
            telemetry: telemetrySnapshot(
              rawResponse: rawResponseBuffer.toString(),
              finishReason: finishReason,
              error: providerError,
            ),
          ),
          StackTrace.current,
        );
        unawaited(eventController.close());
        unawaited(cancelResponseStream());
        return;
      }

      emitGeneratedMediaIfPresent(decoded);

      // 按协议分派流事件。
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
            unawaited(cancelResponseStream());
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
          citations: citations,
          collectCitations: model.protocolType == AiProtocolType.mimo,
          usage: () => usage,
          setUsage: (value) => usage = value,
          emitEvent: emitEvent,
          setFinishReason: (value) => finishReason = value,
        );
      }
      if (toolCalls.length > _maxRetainedStreamToolCalls) {
        toolCalls.clear();
        failStream('AI 响应中的工具调用数量超过安全上限。');
      }
    }

    bool isStreamComplete() => resultCompleter.isCompleted;

    void processChunk(String chunk) {
      final accepted = _processBoundedSseChunk(
        chunk: chunk,
        carry: lineBuffer,
        maxBufferLength: maxStreamLineBufferBytes,
        isComplete: isStreamComplete,
        processEventBlock: processEventBlock,
      );
      if (!accepted) {
        failStream('AI 响应流单个事件超过安全上限。');
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
            if (lineBuffer.isNotEmpty &&
                lineBuffer.length <= maxStreamLineBufferBytes) {
              processEventBlock(lineBuffer.pending);
            }
            completeStreamResult('stream_closed');
          },
          cancelOnError: true,
        );
    eventController.onPause = () => responseSubscription?.pause();
    eventController.onResume = () => responseSubscription?.resume();
    eventController.onCancel = () async {
      if (resultCompleter.isCompleted) return;
      completeStreamResult('event_stream_cancelled', wasCancelled: true);
      await cancelResponseStream();
    };

    return AiChatStreamingResponse(
      events: eventController.stream,
      result: resultCompleter.future,
      cancel: () async {
        completeStreamResult('cancelled', wasCancelled: true);
        await cancelResponseStream();
      },
    );
  }

  Future<AiChatStreamingResponse> _sendResponsesStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    required List<AiToolDefinition> tools,
    required AiCreationRequest creationRequest,
    required Duration timeout,
    required Duration streamIdleTimeout,
    Future<void>? cancelSignal,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
    AiInputCacheRuntimeConfig? inputCacheConfig,
  }) async {
    final streamCancellationTimeout = _boundedStreamCancellationTimeout(
      streamIdleTimeout,
    );
    _responsesService ??= AiResponsesService(client: _client);
    var request = await _responsesService!.buildChatRequest(
      model: model,
      messages: messages,
      tools: tools,
      imageGenerationOptions: creationRequest.mode == AiCreationMode.image
          ? creationRequest.options
          : null,
      stream: true,
      inputCacheConfig: inputCacheConfig,
    );
    if (AiPromptCacheRetentionPolicy.wasRecentlyRejected(
      requestUrl: request.url,
      requestBody: request.body,
    )) {
      request = AiResponsesRequestBlueprint(
        url: request.url,
        method: request.method,
        headers: request.headers,
        body: AiPromptCacheRetentionPolicy.withoutMarker(request.body),
      );
    }
    final requestFallbacks = <String>[];
    late DateTime streamStartedAt;
    late Map<String, String> capturedHeaders;
    late Map<String, Object?> capturedBody;

    Future<http.StreamedResponse?> openResponsesStream(
      AiResponsesRequestBlueprint nextRequest,
    ) async {
      request = nextRequest;
      streamStartedAt = DateTime.now().toUtc();
      capturedHeaders = Map<String, String>.unmodifiable(request.headers);
      capturedBody = request.body;
      onRequestStarted?.call(
        AiChatRequestTelemetry(
          requestUrl: request.url,
          requestMethod: request.method,
          requestHeaders: capturedHeaders,
          requestBody: capturedBody,
          startedAt: streamStartedAt,
          requestFallbacks: List<String>.unmodifiable(requestFallbacks),
        ),
      );
      final streamedResponseFuture = _sendHttpRequestWithRedirects(
        client: _client,
        method: request.method,
        uri: Uri.parse(request.url),
        headers: request.headers,
        body: jsonEncode(request.body),
        timeout: timeout,
        cancelSignal: cancelSignal,
      );
      if (cancelSignal == null) {
        return streamedResponseFuture;
      }
      final firstResult = await Future.any(<Future<Object?>>[
        streamedResponseFuture,
        _cancelSignalSentinel(cancelSignal, _cancelledStreamSentinel),
      ]);
      if (identical(firstResult, _cancelledStreamSentinel)) {
        unawaited(
          streamedResponseFuture
              .then(
                (response) => _cancelLateStreamedResponse(
                  response,
                  timeout: streamCancellationTimeout,
                ),
              )
              .catchError((Object _, StackTrace stackTrace) {}),
        );
        return null;
      }
      return firstResult as http.StreamedResponse;
    }

    var streamedResponse = await openResponsesStream(request);
    if (streamedResponse == null) {
      return AiChatStreamingResponse.cancelled();
    }
    String? responsesErrorBody;
    if (isHttpFailureStatus(streamedResponse.statusCode)) {
      responsesErrorBody = await _readChatHttpErrorBody(
        streamedResponse,
        timeout: streamIdleTimeout,
      );
      if (AiPromptCacheRetentionPolicy.shouldRetryWithoutMarker(
        statusCode: streamedResponse.statusCode,
        errorBody: responsesErrorBody,
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
        final retryRequest = AiResponsesRequestBlueprint(
          url: request.url,
          method: request.method,
          headers: request.headers,
          body: AiPromptCacheRetentionPolicy.withoutMarker(request.body),
        );
        streamedResponse = await openResponsesStream(retryRequest);
        if (streamedResponse == null) {
          return AiChatStreamingResponse.cancelled();
        }
        responsesErrorBody = isHttpSuccessStatus(streamedResponse.statusCode)
            ? null
            : await _readChatHttpErrorBody(
                streamedResponse,
                timeout: streamIdleTimeout,
              );
      }
      if (isHttpFailureStatus(streamedResponse.statusCode) &&
          AiPromptCacheAffinity.shouldRetryWithoutMarkers(
            statusCode: streamedResponse.statusCode,
            errorBody: responsesErrorBody ?? '',
            requestBody: request.body,
            requestHeaders: request.headers,
          )) {
        _addRequestFallback(
          requestFallbacks,
          aiChatRequestFallbackCacheAffinityRejected,
        );
        final retryRequest = AiResponsesRequestBlueprint(
          url: request.url,
          method: request.method,
          headers: AiPromptCacheAffinity.withoutHeaderMarkers(request.headers),
          body: AiPromptCacheAffinity.withoutBodyMarkers(request.body),
        );
        streamedResponse = await openResponsesStream(retryRequest);
        if (streamedResponse == null) {
          return AiChatStreamingResponse.cancelled();
        }
        if (isHttpSuccessStatus(streamedResponse.statusCode)) {
          responsesErrorBody = null;
        } else {
          responsesErrorBody = await _readChatHttpErrorBody(
            streamedResponse,
            timeout: streamIdleTimeout,
          );
        }
      }
    }
    if (isHttpFailureStatus(streamedResponse.statusCode)) {
      if (AiThinkingRequestPolicy.shouldRetryWithoutMarkers(
        statusCode: streamedResponse.statusCode,
        errorBody: responsesErrorBody ?? '',
        requestBody: request.body,
      )) {
        _addRequestFallback(
          requestFallbacks,
          aiChatRequestFallbackThinkingMarkersRejected,
        );
        final retryRequest = AiResponsesRequestBlueprint(
          url: request.url,
          method: request.method,
          headers: request.headers,
          body: AiThinkingRequestPolicy.withoutRequestMarkers(request.body),
        );
        streamedResponse = await openResponsesStream(retryRequest);
        if (streamedResponse == null) {
          return AiChatStreamingResponse.cancelled();
        }
        if (isHttpSuccessStatus(streamedResponse.statusCode)) {
          // 重试成功，继续读取 SSE。
        } else {
          responsesErrorBody = await _readChatHttpErrorBody(
            streamedResponse,
            timeout: streamIdleTimeout,
          );
        }
      }
    }
    if (isHttpFailureStatus(streamedResponse.statusCode)) {
      final errorBody =
          responsesErrorBody ??
          await _readChatHttpErrorBody(
            streamedResponse,
            timeout: streamIdleTimeout,
          );
      final endedAt = DateTime.now().toUtc();
      throw AiResponsesHttpException(
        statusCode: streamedResponse.statusCode,
        body: errorBody,
        request: request,
        startedAt: streamStartedAt,
        endedAt: endedAt,
        requestFallbacks: List<String>.unmodifiable(requestFallbacks),
      );
    }

    final eventController = StreamController<AiChatStreamEvent>(sync: true);
    final resultCompleter = Completer<AiChatStreamResult>();
    final textBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final toolCalls = <int, AiResponsesStreamToolCall>{};
    final rawResponseBuffer = StringBuffer();
    final lineBuffer = _SseLineCarry();
    AiTokenUsage? usage;
    String? finishReason;
    Map<String, Object?>? completedResponse;
    Future<void>? eventControllerCloseFuture;

    Future<void> closeEvents() {
      return eventControllerCloseFuture ??= eventController.close();
    }

    StreamSubscription<String>? responseSubscription;
    Future<void>? responseSubscriptionCancelFuture;
    var finalizing = false;

    Future<void> cancelResponseStream() {
      final subscription = responseSubscription;
      if (subscription == null) return Future<void>.value();
      return responseSubscriptionCancelFuture ??= _cancelStreamSubscription(
        subscription,
        timeout: streamCancellationTimeout,
        logContext: '取消 Responses 响应流',
      );
    }

    void emitEvent(AiChatStreamEvent event) {
      if (!resultCompleter.isCompleted && !eventController.isClosed) {
        eventController.add(event);
      }
    }

    void failStream(String message) {
      if (resultCompleter.isCompleted) return;
      resultCompleter.completeError(
        AiChatException(
          message,
          telemetry: AiChatRequestTelemetry(
            requestUrl: request.url,
            requestMethod: request.method,
            requestHeaders: capturedHeaders,
            requestBody: capturedBody,
            rawResponse: rawResponseBuffer.toString(),
            startedAt: streamStartedAt,
            endedAt: DateTime.now().toUtc(),
            finishReason: finishReason,
            error: message,
            requestFallbacks: List<String>.unmodifiable(requestFallbacks),
          ),
        ),
        StackTrace.current,
      );
      unawaited(closeEvents());
      unawaited(cancelResponseStream());
    }

    void appendFinalText(String value) {
      final normalized = value.trim();
      if (normalized.isEmpty) return;
      final current = textBuffer.toString();
      if (current.trim().isEmpty) {
        textBuffer
          ..clear()
          ..write(normalized);
        emitEvent(AiChatStreamEvent.textDelta(normalized));
        return;
      }
      if (normalized == current.trim()) return;
      if (!normalized.startsWith(current)) {
        textBuffer
          ..clear()
          ..write(normalized);
        return;
      }
      final delta = normalized.substring(current.length);
      if (delta.isEmpty) return;
      textBuffer.write(delta);
      emitEvent(AiChatStreamEvent.textDelta(delta));
    }

    void appendFinalReasoning(String? value) {
      final normalized = nullIfBlank(value);
      if (normalized == null) return;
      final current = reasoningBuffer.toString();
      if (current.trim().isEmpty) {
        reasoningBuffer
          ..clear()
          ..write(normalized);
        emitEvent(AiChatStreamEvent.reasoningDelta(normalized));
        return;
      }
      if (normalized == current.trim()) return;
      if (!normalized.startsWith(current)) {
        reasoningBuffer
          ..clear()
          ..write(normalized);
        return;
      }
      final delta = normalized.substring(current.length);
      if (delta.isEmpty) return;
      reasoningBuffer.write(delta);
      emitEvent(AiChatStreamEvent.reasoningDelta(delta));
    }

    Future<void> completeStreamResult({bool wasCancelled = false}) async {
      if (resultCompleter.isCompleted || finalizing) return;
      finalizing = true;
      AiResponsesParsedPayload? parsed;
      if (!wasCancelled && completedResponse != null) {
        try {
          parsed = await _responsesService!.parseResponsePayload(
            completedResponse,
          );
          appendFinalText(parsed.text);
          appendFinalReasoning(parsed.reasoning);
          if (parsed.usage != null && !parsed.usage!.isEmpty) {
            usage = AiTokenUsageParser.carryForward(usage, parsed.usage!);
          }
          finishReason ??= parsed.finishReason;
        } catch (error, stackTrace) {
          if (!resultCompleter.isCompleted) {
            resultCompleter.completeError(error, stackTrace);
          }
          unawaited(closeEvents());
          return;
        }
      }
      if (resultCompleter.isCompleted) return;
      final streamedToolCalls = toolCalls.entries.toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
      final parsedStreamToolCalls = streamedToolCalls
          .map((entry) => entry.value.toToolCall(entry.key))
          .whereType<AiToolCall>()
          .toList(growable: false);
      final replyExtraction = extractDsmlToolCalls(textBuffer.toString());
      final resolvedToolCalls = parsed?.toolCalls.isNotEmpty == true
          ? parsed!.toolCalls
          : parsedStreamToolCalls.isNotEmpty
          ? parsedStreamToolCalls
          : replyExtraction.toolCalls;
      if (resolvedToolCalls.length > _maxRetainedStreamToolCalls) {
        toolCalls.clear();
        failStream('AI 响应中的工具调用数量超过安全上限。');
        return;
      }
      if (!wasCancelled &&
          completedResponse == null &&
          replyExtraction.sanitizedText.isEmpty &&
          reasoningBuffer.toString().trim().isEmpty &&
          resolvedToolCalls.isEmpty) {
        resultCompleter.completeError(
          const AiResponsesPayloadException('Responses API 响应流未返回助手内容或工具调用。'),
          StackTrace.current,
        );
        unawaited(closeEvents());
        return;
      }
      final effectiveFinishReason =
          finishReason ??
          (resolvedToolCalls.isNotEmpty
              ? 'tool_calls'
              : replyExtraction.hasTrailingIncompleteMarkup
              ? 'length'
              : null);
      final endedAt = DateTime.now().toUtc();
      resultCompleter.complete(
        AiChatStreamResult(
          reply: replyExtraction.sanitizedText,
          reasoning: reasoningBuffer.toString().trim(),
          toolCalls: resolvedToolCalls,
          wasCancelled: wasCancelled,
          usage: usage,
          rawResponse: rawResponseBuffer.toString(),
          finishReason: effectiveFinishReason,
          requestUrl: request.url,
          requestMethod: request.method,
          requestHeaders: capturedHeaders,
          requestBody: capturedBody,
          startedAt: streamStartedAt,
          endedAt: endedAt,
          durationMs: endedAt.difference(streamStartedAt).inMilliseconds,
          requestFallbacks: List<String>.unmodifiable(requestFallbacks),
        ),
      );
      unawaited(closeEvents());
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
      if (!_tryAppendRawStreamEvent(rawResponseBuffer, data)) {
        failStream('AI 响应流超过累计保留上限。');
        return;
      }
      late final Object? decoded;
      try {
        decoded = jsonDecode(data);
      } catch (_) {
        return;
      }
      if (decoded is! Map<String, Object?>) return;
      final providerError = _providerStreamErrorMessage(decoded);
      if (providerError != null) {
        resultCompleter.completeError(
          AiChatException(
            providerError,
            telemetry: AiChatRequestTelemetry(
              requestUrl: request.url,
              requestMethod: request.method,
              requestHeaders: capturedHeaders,
              requestBody: capturedBody,
              rawResponse: rawResponseBuffer.toString(),
              startedAt: streamStartedAt,
              endedAt: DateTime.now().toUtc(),
              error: providerError,
              requestFallbacks: List<String>.unmodifiable(requestFallbacks),
            ),
          ),
          StackTrace.current,
        );
        unawaited(closeEvents());
        unawaited(cancelResponseStream());
        return;
      }
      final eventType = '${decoded['type'] ?? ''}';
      if (eventType == 'response.failed' || eventType == 'error') {
        final responseError =
            decoded['response'] ?? decoded['error'] ?? decoded;
        final message = extractApiErrorMessage(
          jsonEncode(responseError),
          emptyFallback: 'Responses API 响应流失败。',
        );
        if (!resultCompleter.isCompleted) {
          resultCompleter.completeError(
            AiChatException(
              message,
              telemetry: AiChatRequestTelemetry(
                requestUrl: request.url,
                requestMethod: request.method,
                requestHeaders: capturedHeaders,
                requestBody: capturedBody,
                rawResponse: rawResponseBuffer.toString(),
                startedAt: streamStartedAt,
                endedAt: DateTime.now().toUtc(),
                error: message,
                requestFallbacks: List<String>.unmodifiable(requestFallbacks),
              ),
            ),
            StackTrace.current,
          );
        }
        unawaited(closeEvents());
        unawaited(cancelResponseStream());
        return;
      }
      _responsesService!.parseSseEvent(
        decoded,
        textBuffer: textBuffer,
        reasoningBuffer: reasoningBuffer,
        toolCalls: toolCalls,
        usage: () => usage,
        setUsage: (value) => usage = value,
        emitEvent: emitEvent,
        setFinishReason: (value) => finishReason = value,
        setCompletedResponse: (value) => completedResponse = value,
      );
      if (toolCalls.length > _maxRetainedStreamToolCalls) {
        toolCalls.clear();
        failStream('AI 响应中的工具调用数量超过安全上限。');
      }
    }

    bool isStreamComplete() => resultCompleter.isCompleted;

    void processChunk(String chunk) {
      final accepted = _processBoundedSseChunk(
        chunk: chunk,
        carry: lineBuffer,
        maxBufferLength: maxStreamLineBufferBytes,
        isComplete: isStreamComplete,
        processEventBlock: processEventBlock,
      );
      if (!accepted) {
        failStream('AI 响应流单个事件超过安全上限。');
      }
    }

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
              unawaited(closeEvents());
            }
          },
          onDone: () {
            if (lineBuffer.isNotEmpty &&
                lineBuffer.length <= maxStreamLineBufferBytes) {
              processEventBlock(lineBuffer.pending);
            }
            unawaited(completeStreamResult());
          },
          cancelOnError: true,
        );
    eventController.onPause = () => responseSubscription?.pause();
    eventController.onResume = () => responseSubscription?.resume();
    eventController.onCancel = () async {
      if (resultCompleter.isCompleted) return;
      await completeStreamResult(wasCancelled: true);
      await cancelResponseStream();
    };

    return AiChatStreamingResponse(
      events: eventController.stream,
      result: resultCompleter.future,
      cancel: () async {
        await completeStreamResult(wasCancelled: true);
        await cancelResponseStream();
        // 单订阅流要在监听者收到结束事件后才完成 close，取消流程不能因此阻塞。
        unawaited(closeEvents());
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
    AiInputCacheRuntimeConfig? inputCacheConfig,
    List<String> initialRequestFallbacks = const <String>[],
    bool routeThroughChatRouting = false,
  }) async {
    final controller = StreamController<AiChatStreamEvent>(sync: true);
    final completer = Completer<AiChatStreamResult>();
    // 内部取消信号确保 `cancel()` 同时释放包装层和底层可取消请求。
    final internalCancelCompleter = Completer<void>();
    final effectiveCancelSignal = combineCancelSignals(<Future<void>?>[
      internalCancelCompleter.future,
      cancelSignal,
    ])!;
    var cancelled = false;
    Future<void>? controllerCloseFuture;

    void closeEvents() {
      controllerCloseFuture ??= controller.close();
    }

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

    controller.onCancel = () {
      if (!completer.isCompleted) completeCancelled();
    };

    unawaited(() async {
      try {
        final Future<AiChatCompletion> completionFuture;
        if (!routeThroughChatRouting &&
            usesDedicatedMediaGenerationEndpoint(model, creationRequest)) {
          completionFuture = _sendMediaGenerationCompletion(
            model: model,
            messages: messages,
            creationRequest: creationRequest,
            timeout: timeout,
            cancelSignal: effectiveCancelSignal,
          );
        } else {
          completionFuture = _sendMessage(
            model: model,
            messages: messages,
            tools: tools,
            responseModalities: responseModalities,
            creationRequest: creationRequest,
            timeout: timeout,
            onRequestStarted: onRequestStarted,
            inputCacheConfig: inputCacheConfig,
            cancelSignal: effectiveCancelSignal,
          );
        }
        // 保留竞速，确保不可中止的供应商链路也能立即释放 UI 状态。
        final raceFutures = <Future<Object?>>[
          completionFuture,
          _cancelSignalSentinel(
            effectiveCancelSignal,
            _cancelledStreamSentinel,
          ),
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
              requestFallbacks: <String>[
                ...initialRequestFallbacks,
                ...completion.requestFallbacks,
              ],
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
        // 单订阅流可能尚未被监听，关闭 Future 此时不会完成。
        closeEvents();
      }
    }());
    return AiChatStreamingResponse(
      events: controller.stream,
      result: completer.future,
      cancel: () async {
        completeCancelled();
        closeEvents();
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
      _cancelSignalSentinel(cancelSignal, _cancelledRequestSentinel),
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

  /// 失败路径的降级链：能拿到遥测就用遥测里的，拿不到按「未发生降级」计。
  ///
  /// 用量归因要按实际命中的 API family 记账，取不到降级链时不能凭空猜测，
  /// 否则失败请求会被记到错误的渠道上。
  List<String> _requestFallbacksFromError(Object error) {
    if (error is! AiChatException) return const <String>[];
    return error.telemetry?.requestFallbacks ?? const <String>[];
  }

  String _usageApiFamily({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    required List<AiToolDefinition> tools,
    required List<String> responseModalities,
    required AiCreationRequest request,
    required List<String> requestFallbacks,
  }) {
    if (request.isActive) return 'media_${request.mode.name}';
    var responsesSelected = false;
    try {
      responsesSelected = _canUseResponsesFamily(
        model: model,
        messages: messages,
        tools: tools,
        responseModalities: responseModalities,
        creationRequest: request,
      );
    } catch (error, stack) {
      silentLog('ai_chat_service', '判断用量接口类型', error, stack);
    }
    if (responsesSelected &&
        !requestFallbacks.contains(aiChatRequestFallbackResponsesUnsupported)) {
      return AiApiFamily.responses.storageValue;
    }
    return switch (model.apiDialect) {
      AiApiDialect.anthropicNative => AiApiFamily.messages.storageValue,
      AiApiDialect.geminiNative => 'generate_content',
      AiApiDialect.openAiCompat => AiApiFamily.chatCompletions.storageValue,
    };
  }

  int _requestCharacterCount(
    List<AiChatTurn> messages,
    List<AiToolDefinition> tools, {
    required AiModelConfig model,
    required AiCreationRequest creationRequest,
  }) {
    if (usesDedicatedMediaGenerationEndpoint(model, creationRequest)) {
      return mediaGenerationInputTurn(messages)?.content.length ?? 0;
    }
    var total = messages.fold<int>(
      0,
      (sum, message) =>
          sum +
          message.promptCharacterCount +
          (message.reasoningContent?.length ?? 0) +
          message.toolCalls.fold<int>(
            0,
            (toolSum, call) =>
                toolSum + call.name.length + call.arguments.length,
          ),
    );
    for (final tool in tools) {
      total += tool.name.length + tool.description.length;
      try {
        total += jsonEncode(tool.parameters).length;
      } catch (_) {
        total += tool.parameters.toString().length;
      }
    }
    return total;
  }

  int _completionCharacterCount(
    AiChatCompletion completion, {
    required AiModelConfig model,
    required AiCreationRequest creationRequest,
  }) {
    if (usesDedicatedMediaGenerationEndpoint(model, creationRequest)) return 0;
    return completion.reply.length +
        (completion.reasoningContent?.length ?? 0) +
        completion.toolCalls.fold<int>(
          0,
          (sum, call) => sum + call.name.length + call.arguments.length,
        );
  }

  int _streamResultCharacterCount(
    AiChatStreamResult result, {
    required AiModelConfig model,
    required AiCreationRequest creationRequest,
  }) {
    if (usesDedicatedMediaGenerationEndpoint(model, creationRequest)) return 0;
    return result.reply.length +
        result.reasoning.length +
        result.toolCalls.fold<int>(
          0,
          (sum, call) => sum + call.name.length + call.arguments.length,
        );
  }

  @override
  Future<AiModelTestResult> testModel(AiModelConfig model) async {
    if (model.normalizedBaseUrl.isEmpty) {
      throw const AiChatException('缺少 Base URL。');
    }
    final modelId = nullIfBlank(model.modelId);
    if (modelId == null) {
      throw const AiChatException('缺少模型 ID。');
    }
    final baseProbeModel = model.copyWith(
      clearMaxTokens: true,
      clearTemperature: true,
    );

    Future<AiChatCompletion> probe(
      AiModelConfig probeModel, {
      required bool allowResponsesFallback,
    }) {
      return AiUsageTraceContext.runDerived(
        source: AiUsageSource.modelTest,
        operation: 'availability_probe',
        body: () => sendMessage(
          model: probeModel,
          messages: const <AiChatTurn>[
            AiChatTurn(
              role: AiChatRole.user,
              content: _availabilityProbePrompt,
            ),
          ],
          timeout: const Duration(seconds: 20),
          allowResponsesFallback: allowResponsesFallback,
        ),
      );
    }

    AiModelTestResult verifiedResult(
      AiChatCompletion completion,
      AiApiFamily family,
    ) {
      final normalizedReply = nullIfBlank(completion.reply);
      if (normalizedReply == null) {
        throw AiChatException(
          '助手回复为空。',
          telemetry:
              completion.requestUrl == null && completion.requestMethod == null
              ? null
              : AiChatRequestTelemetry(
                  requestUrl: completion.requestUrl,
                  requestMethod: completion.requestMethod,
                  requestHeaders: completion.requestHeaders,
                  requestBody: completion.requestBody,
                  rawResponse: completion.rawResponse,
                  startedAt: completion.startedAt,
                  endedAt: completion.endedAt,
                  durationMs: completion.durationMs,
                  error: '助手回复为空。',
                ),
        );
      }
      return AiModelTestResult(
        reply: normalizedReply,
        chatApiFamily: family,
        requestUrl: completion.requestUrl,
        requestMethod: completion.requestMethod,
        durationMs: completion.durationMs,
      );
    }

    final fallbackFamily = AiProtocolRegistry.adapterForModel(
      baseProbeModel,
    ).operationFamily;
    final testsResponses =
        baseProbeModel.apiDialect == AiApiDialect.openAiCompat &&
        fallbackFamily == AiApiFamily.chatCompletions;
    if (!testsResponses) {
      try {
        return verifiedResult(
          await probe(baseProbeModel, allowResponsesFallback: true),
          fallbackFamily,
        );
      } on AiChatException catch (error) {
        if (inferAiApiDialect(baseProbeModel.protocolType) !=
            AiApiDialect.openAiCompat) {
          rethrow;
        }
        throw await _decorateProviderProbeFailure(
          baseProbeModel,
          error,
          timeout: const Duration(seconds: 12),
        );
      }
    }

    final responsesCapabilities = Map<AiApiFamily, String>.from(
      baseProbeModel.capabilityOverrides,
    )..[AiApiFamily.responses] = 'supported';
    final responsesProbeModel = baseProbeModel.copyWith(
      capabilityOverrides: responsesCapabilities,
    );
    late final AiChatException responsesFailure;
    try {
      return verifiedResult(
        await probe(responsesProbeModel, allowResponsesFallback: false),
        AiApiFamily.responses,
      );
    } on AiChatException catch (error) {
      responsesFailure = error;
    }

    final chatCapabilities = Map<AiApiFamily, String>.from(
      baseProbeModel.capabilityOverrides,
    )..[AiApiFamily.responses] = 'disabled';
    final chatProbeModel = baseProbeModel.copyWith(
      capabilityOverrides: chatCapabilities,
    );
    try {
      return verifiedResult(
        await probe(chatProbeModel, allowResponsesFallback: false),
        AiApiFamily.chatCompletions,
      );
    } on AiChatException catch (chatFailure) {
      final combinedFailure = AiChatException(
        StructuredErrorText.pick(
          zh: 'Responses 与 Chat Completions 接口均测试失败，详见下方分端点诊断。',
          en: 'Both Responses and Chat Completions endpoints failed. See per-endpoint diagnostics below.',
        ),
        telemetry: chatFailure.telemetry,
        sources: <AiErrorSource>[
          AiErrorSource(
            label: StructuredErrorText.pick(
              zh: 'Responses 接口',
              en: 'Responses endpoint',
            ),
            body: responsesFailure.message,
          ),
          AiErrorSource(
            label: StructuredErrorText.pick(
              zh: 'Chat Completions 接口',
              en: 'Chat Completions endpoint',
            ),
            body: chatFailure.message,
          ),
        ],
      );
      throw await _decorateProviderProbeFailure(
        chatProbeModel,
        combinedFailure,
        timeout: const Duration(seconds: 12),
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requestSlots.cancelWaiters();
    for (final abort in _activeRequestAborts.toList(growable: false)) {
      if (!abort.isCompleted) abort.complete();
    }
    _activeRequestAborts.clear();
    _responsesCompatibilityStopwatch.stop();
    _unsupportedResponsesEndpoints.clear();
    _unsupportedResponsesRequestShapes.clear();
    _responsesService?.dispose();
    _responsesService = null;
    if (_ownsImageService) {
      _imageService.dispose();
    }
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<Completer<void>> _beginRequest(Future<void>? cancelSignal) async {
    if (_disposed) throw StateError('AI 聊天服务已关闭。');
    late final bool acquired;
    try {
      acquired = await _requestSlots.acquireWithin(
        _requestQueueTimeout,
        cancelSignal: cancelSignal,
      );
    } on StateError {
      if (_disposed) throw StateError('AI 聊天服务已关闭。');
      throw const AiChatException('AI 聊天请求排队已满，请稍后再试。');
    }
    if (!acquired) {
      if (_disposed) throw StateError('AI 聊天服务已关闭。');
      if (await isCancelSignalCompleted(cancelSignal)) {
        throw const AiChatCancelledException();
      }
      throw TimeoutException('AI 聊天请求排队超时。', _requestQueueTimeout);
    }
    if (_disposed) {
      _requestSlots.release();
      throw StateError('AI 聊天服务已关闭。');
    }
    final abort = Completer<void>();
    _activeRequestAborts.add(abort);
    return abort;
  }

  void _finishRequest(Completer<void> abort) {
    if (!abort.isCompleted) abort.complete();
    _activeRequestAborts.remove(abort);
    _requestSlots.release();
  }
}

/// SSE 行缓冲。
///
/// 刻意用可变 String 而不是 StringBuffer：解析每轮都要读「当前尚未消费的
/// 全部内容」，而 StringBuffer 每次读都得整体 toString 再重建。一个 TCP
/// 分片里若含 k 个完整事件，就会做 k 次「整缓冲 toString + 整余量 substring
/// + 整余量 write」，在上限 4 MiB 的缓冲上退化为 O(k·n) 字符拷贝——而这条
/// 路径是流式渲染最热的一环。
class _SseLineCarry {
  String pending = '';

  bool get isNotEmpty => pending.isNotEmpty;

  int get length => pending.length;
}

bool _processBoundedSseChunk({
  required String chunk,
  required _SseLineCarry carry,
  required int maxBufferLength,
  required bool Function() isComplete,
  required void Function(String block) processEventBlock,
}) {
  var pending =
      carry.pending + chunk.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // 已消费前缀的游标：整轮只在最后切一次，循环内不复制字符串。
  var cut = 0;
  while (!isComplete()) {
    if (pending.length - cut < 2) break;
    final separatorIndex = pending.indexOf('\n\n', cut);
    if (separatorIndex < 0) {
      if (pending.length - cut > maxBufferLength) {
        carry.pending = '';
        return false;
      }
      break;
    }
    final block = pending.substring(cut, separatorIndex);
    cut = separatorIndex + 2;
    if (block.length > maxBufferLength) {
      carry.pending = '';
      return false;
    }
    processEventBlock(block);
  }
  carry.pending = cut == 0 ? pending : pending.substring(cut);
  return true;
}

const Object _cancelledRequestSentinel = Object();
const Object _cancelledStreamSentinel = Object();

Future<Object?> _cancelSignalSentinel(
  Future<void> cancelSignal,
  Object sentinel,
) {
  return cancelSignal.then<Object?>(
    (_) => sentinel,
    onError: (Object _, StackTrace _) => sentinel,
  );
}

class _SyntheticStreamCancelledException implements Exception {}

String? _providerStreamErrorMessage(Map<String, Object?> payload) {
  final baseResponse = payload['base_resp'];
  if (baseResponse is! Map) return null;
  final values = stringKeyedMapFromValue(baseResponse);
  final statusCode = optionalIntFromValue(values['status_code']);
  if (statusCode == null || statusCode == 0) return null;
  final statusMessage =
      optionalStringFromValue(values['status_msg']) ?? '供应商请求失败。';
  return '供应商响应流失败（$statusCode）：$statusMessage';
}

String? _mimoWebSearchWarningFromPayload(Map<String, Object?> payload) {
  final candidates = <Object?>[payload['web_search'], payload['webSearch']];
  final choices = payload['choices'];
  if (choices is List && choices.isNotEmpty && choices.first is Map) {
    final choice = choices.first as Map;
    candidates.add(choice['delta'] ?? choice['message']);
  }
  return firstErrorMessageFromPayloads(candidates);
}

/// 处理单个 OpenAI 兼容 SSE 事件块。
void _processOpenAiStreamEvent(
  Map<String, Object?> decoded, {
  required StringBuffer textBuffer,
  required StringBuffer reasoningBuffer,
  required Map<int, _MutableToolCall> toolCalls,
  required Map<String, String> citations,
  required bool collectCitations,
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
      // 合并上一帧，保留仅在首尾分片出现的缓存统计字段。
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
    // 记录结束原因，用于区分正常结束、截断和工具调用。
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
    if (collectCitations) {
      _collectStreamCitations(delta['annotations'], citations);
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
      // OpenAI 流协议为每个工具调用分配稳定索引。兼容服务缺失索引时先按 ID
      // 匹配，最后才视为最近工具调用的续帧，避免参数错误拼接。
      final id = optionalStringFromValue(toolCallMap['id']) ?? '';
      final rawIndex = optionalIntegralIntFromValue(toolCallMap['index']);
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

void _collectStreamCitations(
  Object? rawAnnotations,
  Map<String, String> citations,
) {
  if (rawAnnotations is! List) return;
  for (final raw in rawAnnotations) {
    if (raw is! Map) continue;
    final annotation = stringKeyedMapFromValue(raw);
    final citation = annotation['url_citation'] is Map
        ? stringKeyedMapFromValue(annotation['url_citation'])
        : annotation;
    final url = optionalStringFromValue(citation['url']);
    if (url == null || citations.containsKey(url)) continue;
    final rawTitle =
        optionalStringFromValue(citation['title']) ??
        optionalStringFromValue(citation['site_name']) ??
        url;
    citations[url] = rawTitle.replaceAll('[', '').replaceAll(']', '');
  }
}

/// 处理单个 Claude/Anthropic SSE 事件块。
///
/// Claude SSE 使用顶层 `type` 标识事件类型：
///   - `message_start`：初始消息元数据与用量
///   - `ping`：心跳，忽略
///   - `content_block_start`：内容块开始
///   - `content_block_delta`：文本或思考增量
///   - `content_block_stop`：内容块结束
///   - `message_delta`：结束原因与最终用量
///   - `message_stop`：消息结束
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
      // 提取初始用量。
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
      // 记录工具调用块的 ID 和名称。
      final contentBlock = decoded['content_block'];
      if (contentBlock is Map<String, Object?>) {
        final blockType = stringFromValue(contentBlock['type']);
        if (blockType == 'tool_use') {
          final index =
              optionalIntegralIntFromValue(decoded['index']) ??
              toolCalls.length;
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
        // 暂不处理签名分片。
      } else if (deltaType == 'input_json_delta') {
        // Claude 工具调用参数分片。
        final partialJson = '${delta['partial_json'] ?? ''}';
        final index =
            optionalIntegralIntFromValue(decoded['index']) ?? toolCalls.length;
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
      // 提取最终用量和结束原因。
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
          // 与初始帧合并，保留最终帧未重复返回的缓存统计字段。
          final merged = AiTokenUsageParser.carryForward(usage(), parsedUsage);
          setUsage(merged);
          emitEvent(AiChatStreamEvent.usage(merged));
        }
      }

    case 'message_stop':
      completeStreamResult('claude_message_stop');
      cancelSubscription();

    case 'error':
      // 通用流内错误检测会处理 `error` 字段。
      break;

    default:
      break;
  }
}

/// 处理单个 Gemini SSE 事件块。
///
/// Gemini 流式接口（`?alt=sse`）按分片返回与非流式接口相同的 JSON 结构：
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
/// 工具调用位于 `functionCall` 分片：
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
  // 解析用量元数据。
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

  // 解析候选结果。
  final candidates = decoded['candidates'];
  if (candidates is! List<dynamic>) return;
  for (final candidate in candidates) {
    if (candidate is! Map<String, Object?>) continue;
    // 记录 Gemini 结束原因。
    final geminiFinishReason = optionalStringFromValue(
      candidate['finishReason'],
    );
    if (geminiFinishReason != null) {
      // 将 Gemini 的 `MAX_TOKENS` 统一为 `length`。
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

      // 分片正文不能 trim：分片边界上的空格与换行本身就是正文的一部分，
      // 逐片 trim 会吞掉词间空格与 markdown 的换行结构。与 Anthropic /
      // OpenAI 两个分支的取法保持一致。
      final text = '${part['text'] ?? ''}';

      // 思维链要先判：Gemini 2.5 的 thought 分片同样带 text 字段，
      // 若先消费 text 就永远轮不到这里，思维链会被当作正文写进 textBuffer。
      if (part['thought'] == true) {
        if (text.isNotEmpty) {
          reasoningBuffer.write(text);
          emitEvent(AiChatStreamEvent.reasoningDelta(text));
          continue;
        }
      } else if (text.isNotEmpty) {
        textBuffer.write(text);
        emitEvent(AiChatStreamEvent.textDelta(text));
        continue;
      }

      // 工具调用。
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
  const AiChatException(
    this.message, {
    this.statusCode,
    this.telemetry,
    this.sources,
  });

  final String message;
  final int? statusCode;
  final AiChatRequestTelemetry? telemetry;

  /// 结构化错误源（可选）。非空时表示该错误由多个来源组成（如双端点测试
  /// 同时失败、或原始错误 + 探测补充），对话框按源渲染独立卡片，避免多条
  /// 结构化文案拼接导致标题重复、解析错乱。为 null 时走纯文本旧路径。
  final List<AiErrorSource>? sources;

  @override
  String toString() => message;
}

class AiChatCancelledException implements Exception {
  const AiChatCancelledException([this.message = '请求已取消。']);

  final String message;

  @override
  String toString() => message;
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
        probeDiagnosis = '$modelsLabel\n$summary';
      } else {
        final scanError = nullIfBlank(scanResult.error);
        if (scanError != null) {
          probeDiagnosis =
              '${StructuredErrorText.pick(zh: '模型列表探测也失败了。该 Base URL 可能整体不可用、鉴权方式不匹配，或中转未按 OpenAI 兼容形式暴露接口。', en: 'The models probe also failed. The Base URL may be entirely unavailable, the authentication scheme may not match, or the relay may not expose the interface in an OpenAI-compatible form.')}\n$scanError';
        }
      }
    } catch (_) {
      // 保留原始供应商测试错误作为主要诊断。
    } finally {
      if (ownsScanner) {
        scanner.dispose();
      }
    }

    final hasSources = error.sources != null && error.sources!.isNotEmpty;
    // 有结构化源（双端点测试失败）时，详情文案不再内联探测补充，避免与源卡片
    // 重复；探测补充作为独立源追加。无源（单端点失败）时维持旧的纯文本拼接。
    final detail = _buildProviderProbeDetail(
      error.message,
      telemetry: error.telemetry,
      diagnosis: hasSources ? null : probeDiagnosis,
    );
    final sources = <AiErrorSource>[
      ...?error.sources,
      if (hasSources && probeDiagnosis != null)
        AiErrorSource(
          label: StructuredErrorText.pick(zh: '探测补充', en: 'Probe follow-up'),
          body: probeDiagnosis,
        ),
    ];
    return AiChatException(
      detail,
      statusCode: error.statusCode,
      telemetry: error.telemetry,
      sources: sources.isEmpty ? null : sources,
    );
  }
}

Map<String, Object?> _usageRequestMetadata(
  String? requestUrl,
  String? requestMethod,
  Map<String, String>? requestHeaders,
) {
  final uri = Uri.tryParse(requestUrl?.trim() ?? '');
  final result = <String, Object?>{};
  if (uri != null) {
    result['request_url'] = uri.replace(query: '').toString();
    result['request_host'] = uri.host;
    result['request_port'] = uri.hasPort
        ? uri.port
        : uri.scheme.toLowerCase() == 'https'
        ? 443
        : 80;
  }
  final method = requestMethod?.trim();
  if (method != null && method.isNotEmpty) result['request_method'] = method;
  final userAgent = _requestHeaderValue(requestHeaders, 'user-agent');
  if (userAgent != null && userAgent.isNotEmpty) {
    result['user_agent'] = userAgent.length > 512
        ? userAgent.substring(0, 512)
        : userAgent;
  }
  return result;
}

String? _requestHeaderValue(Map<String, String>? headers, String name) {
  if (headers == null) return null;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() != name) continue;
    final value = entry.value.trim();
    return value.isEmpty ? null : value;
  }
  return null;
}

Map<String, Object?> _usageErrorMetadata(Object error) {
  final telemetry = error is AiChatException ? error.telemetry : null;
  if (telemetry == null) return const <String, Object?>{};
  return _usageRequestMetadata(
    telemetry.requestUrl,
    telemetry.requestMethod,
    telemetry.requestHeaders,
  );
}

String _buildProviderProbeDetail(
  String message, {
  AiChatRequestTelemetry? telemetry,
  String? diagnosis,
}) {
  final base = nullIfBlank(message) ?? '未知的供应商探测错误。';
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
const int _maxChatHttpErrorBytes = kBytesPerMiB;
const int _maxChatHttpResponseBytes = 16 * kBytesPerMiB;
const int _maxRetainedStreamResponseCharacters = 16 * kBytesPerMiB;
const int _maxRetainedStreamToolCalls =
    AiToolCallLimitPolicy.maxSingleRoundToolCallLimit;
const Duration _maxStreamCancellationWait = Duration(seconds: 1);
const Duration _maxRedirectDrainWait = Duration(seconds: 3);

bool _tryAppendRawStreamEvent(StringBuffer buffer, String data) {
  final remaining = _maxRetainedStreamResponseCharacters - buffer.length;
  if (remaining <= 1 || data.length > remaining - 1) return false;
  buffer.writeln(data);
  return true;
}

Future<http.Response> _collectBoundedChatHttpResponse(
  http.StreamedResponse response, {
  required Duration timeout,
}) async {
  final isFailure = isHttpFailureStatus(response.statusCode);
  final maxBytes = isFailure
      ? _maxChatHttpErrorBytes
      : _maxChatHttpResponseBytes;
  if (!isFailure && (response.contentLength ?? 0) > maxBytes) {
    await _cancelLateStreamedResponse(
      response,
      timeout: _boundedStreamCancellationTimeout(timeout),
    );
    throw ByteStreamSizeLimitException(maxBytes);
  }
  final bodyBytes = await readBoundedByteStream(
    response.stream,
    maxBytes: maxBytes,
    idleTimeout: timeout,
    totalTimeout: timeout,
    truncateOnOverflow: isFailure,
  );
  return http.Response.bytes(
    bodyBytes,
    response.statusCode,
    request: response.request,
    headers: response.headers,
    isRedirect: response.isRedirect,
    persistentConnection: response.persistentConnection,
    reasonPhrase: response.reasonPhrase,
  );
}

Future<String> _readChatHttpErrorBody(
  http.StreamedResponse response, {
  required Duration timeout,
  int maxBytes = _maxChatHttpErrorBytes,
}) async {
  try {
    return await readBoundedByteStreamText(
      response.stream,
      maxBytes: maxBytes,
      idleTimeout: timeout,
      totalTimeout: timeout,
      allowMalformed: true,
    );
  } catch (error, stack) {
    silentLog('ai_chat_service', '读取有界 HTTP 错误响应', error, stack);
    return '';
  }
}

Future<void> _drainChatHttpResponse(
  http.StreamedResponse response, {
  required Duration timeout,
}) async {
  final drainTimeout = timeout < _maxRedirectDrainWait
      ? timeout
      : _maxRedirectDrainWait;
  try {
    await drainByteStreamWithTimeout(
      response.stream,
      idleTimeout: drainTimeout,
      totalTimeout: drainTimeout,
    );
  } catch (error, stack) {
    silentLog('ai_chat_service', '丢弃重定向响应正文', error, stack);
  }
}

Duration _boundedStreamCancellationTimeout(Duration streamIdleTimeout) {
  if (streamIdleTimeout > Duration.zero &&
      streamIdleTimeout < _maxStreamCancellationWait) {
    return streamIdleTimeout;
  }
  return _maxStreamCancellationWait;
}

Future<void> _cancelStreamSubscription(
  StreamSubscription<dynamic> subscription, {
  required Duration timeout,
  required String logContext,
}) async {
  await cancelStreamSubscriptionBounded<dynamic>(
    subscription,
    timeout: timeout,
    onError: (error, stack) =>
        silentLog('ai_chat_service', logContext, error, stack),
  );
}

Future<void> _cancelLateStreamedResponse(
  http.StreamedResponse response, {
  required Duration timeout,
}) async {
  await cancelByteStream(
    response.stream,
    timeout: timeout,
    onError: (error, stack) =>
        silentLog('ai_chat_service', '取消延迟返回的流式响应', error, stack),
  );
}

Future<http.StreamedResponse> _sendHttpRequestWithRedirects({
  required http.Client client,
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  String? body,
  required Duration timeout,
  Future<void>? cancelSignal,
}) {
  return sendHttpRequestFollowingRedirects(
    client: client,
    method: method,
    uri: uri,
    headers: headers,
    body: body,
    timeout: timeout,
    maxRedirects: _maxAiChatRedirects,
    additionalSensitiveHeaderNames: const <String>{'x-api-key', 'api-key'},
    cancelSignal: cancelSignal,
    drainResponse: (response) =>
        _drainChatHttpResponse(response, timeout: timeout),
    onTooManyRedirects: (response) async {
      final responseBody = await _readChatHttpErrorBody(
        response,
        timeout: timeout,
        maxBytes: 16 * kBytesPerKiB,
      );
      final responseText = nullIfBlank(responseBody);
      throw AiChatException(
        '重定向次数超过上限（${_maxAiChatRedirects + 1}）'
        '${responseText == null ? '' : '：$responseText'}',
      );
    },
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
      'image' => '![AI 生成的图片]($url)',
      'audio' => '[AI 生成的音频]($url)',
      'video' => '[AI 生成的视频]($url)',
      _ => '[AI 生成的媒体]($url)',
    };
  }
}

_StreamingGeneratedMedia? _extractStreamingGeneratedMedia(Object? value) {
  return _visitStreamingMediaNode(value, allowBareStringMedia: true);
}

const int _maxStreamingMediaUrlChars = 32 * kBytesPerKiB;

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

  final explicitMime = firstNonBlankStringForKeys(map, const <String>[
    'mime_type',
    'mimeType',
    'content_type',
    'contentType',
    'media_type',
    'mediaType',
  ]);
  final mimeKind = _streamingMediaKindFromMime(explicitMime ?? '');
  final typeKind = _streamingMediaKindFromType(
    firstNonBlankStringForKeys(map, const <String>[
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
  if (isImageMimeType(normalized)) return 'image';
  if (isVideoMimeType(normalized)) return 'video';
  if (isAudioMimeType(normalized)) return 'audio';
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
