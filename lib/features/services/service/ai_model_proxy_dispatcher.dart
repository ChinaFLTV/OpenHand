import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../app/support/system_proxy.dart';
import '../../../shared/net/http_status_utils.dart';
import '../../../shared/net/tcp_port_utils.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/exponential_backoff.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart';
import '../ai_model_proxy_controller.dart';
import '../model/ai_exposure_models.dart';
import '../model/ai_model_proxy_models.dart';
import 'ai_exposure_proxy_client.dart';

const String _kAiModelProxyUserAgent = 'OpenHand-AI-Model-Proxy/1';
const Duration _kAiModelProxyConnectionTimeout = Duration(seconds: 15);
const Duration _kAiModelProxyFailureCooldown = Duration(minutes: 2);
const int _kAiModelProxyFailureCooldownLimit = 256;
const Duration _kAiModelProxyRetryDelayBase = Duration(milliseconds: 150);
const Duration _kAiModelProxyRetryDelayCap = Duration(seconds: 2);
const int _kAiModelProxyDirectFallbackAttempts = 2;
const String _kProxyRouteDirect = 'direct';
const String _kProxyRouteSystem = 'system';
const String _kProxyRoutePool = 'pool';

typedef _ProxyNetworkRoute = ({
  String mode,
  String endpoint,
  String remoteHost,
  String remotePort,
  AiExposureProxyEndpoint? selected,
});

typedef _ProxyRequestContext = ({
  String exposedModel,
  Map<String, String> headers,
  String apiStyle,
  String requestPath,
  int inboundBytes,
  bool stream,
});

typedef _PreparedProxyBackend = ({
  AiModelProxyBackend backend,
  AiModelConfig provider,
  AiModelConfig model,
});

typedef _ProxyDispatchSetup = ({
  List<AiToolDefinition> tools,
  AiModelProxySettings settings,
  int maxAttempts,
  _ProxyRequestContext recordContext,
  _ProxyBackendAttemptPlan backendPlan,
  _ProxyRetryState retryState,
});

const _ProxyNetworkRoute _emptyDirectProxyRoute = (
  mode: _kProxyRouteDirect,
  endpoint: '',
  remoteHost: '',
  remotePort: '',
  selected: null,
);

class AiModelProxyDispatchResult {
  const AiModelProxyDispatchResult({
    required this.reply,
    required this.exposedModel,
    required this.backend,
    required this.durationMs,
    this.usage,
    this.reasoningContent,
    this.toolCalls = const <AiToolCall>[],
    this.rawResponse,
  });

  final String reply;
  final String exposedModel;
  final AiModelProxyBackend backend;
  final int durationMs;
  final AiTokenUsage? usage;
  final String? reasoningContent;
  final List<AiToolCall> toolCalls;
  final String? rawResponse;
}

class AiModelProxyStreamDispatch {
  const AiModelProxyStreamDispatch({
    required this.response,
    required this.exposedModel,
    required this.backend,
  });

  final AiChatStreamingResponse response;
  final String exposedModel;
  final AiModelProxyBackend backend;
}

class AiModelProxyDispatcher {
  AiModelProxyDispatcher({
    required this.controller,
    required this.modelsProvider,
    AiChatClient? chatClient,
  }) : _chatClient = chatClient ?? AiChatService(),
       _usesDefaultChatClient = chatClient == null;

  final AiModelProxyController controller;
  final List<AiModelConfig> Function() modelsProvider;
  final AiChatClient _chatClient;
  final bool _usesDefaultChatClient;
  final Map<String, DateTime> _proxyFailureCooldowns = <String, DateTime>{};

  static const int _maxProxyTools = 256;
  static const int _maxProxyToolNameLength = 128;
  static const int _maxProxyToolDescriptionLength = 16 * 1024;

  /// 返回中转站当前已配置的暴露模型，供 `/v1/models` 端点直接使用。
  Map<String, Object?> buildModelsResponse() =>
      controller.buildModelsResponse();

  Future<AiModelProxyDispatchResult> dispatch({
    required String exposedModel,
    required List<AiChatTurn> messages,
    Map<String, Object?> request = const <String, Object?>{},
    Map<String, String> headers = const <String, String>{},
    String requestPath = '',
    int inboundBytes = 0,
  }) async {
    final (
      :tools,
      :settings,
      :maxAttempts,
      :recordContext,
      :backendPlan,
      :retryState,
    ) = _prepareDispatch(
      exposedModel: exposedModel,
      messages: messages,
      request: request,
      headers: headers,
      requestPath: requestPath,
      inboundBytes: inboundBytes,
      stream: false,
    );
    Object? lastError;
    for (
      var attempt = 0;
      attempt < maxAttempts + _kAiModelProxyDirectFallbackAttempts;
      attempt++
    ) {
      final directFallback = attempt >= maxAttempts;
      if (directFallback && !retryState.directFallbackEnabled) break;
      final prepared = await _prepareBackendAttempt(
        backendPlan: backendPlan,
        directFallback: directFallback,
        request: request,
        headers: headers,
        context: recordContext,
        settings: settings,
        attempt: attempt,
        maxAttempts: maxAttempts,
      );
      if (prepared == null) continue;
      final (:backend, :provider, :model) = prepared;
      final startedAt = DateTime.now();
      var network = _emptyDirectProxyRoute;
      _RoutedChatClient? routedClient;
      var directRouteFallback = directFallback;
      try {
        network = await _resolveAttemptRoute(
          model.baseUrl,
          retryState,
          directFallback: directFallback,
        );
        directRouteFallback = retryState.recordRoute(
          network,
          directFallback: directFallback,
        );
        routedClient = _usesDefaultChatClient
            ? await _createRoutedChatClient(network)
            : null;
        final chatClient = routedClient?.service ?? _chatClient;
        final result = await _runTracedRequest(
          context: recordContext,
          route: network,
          body: () => chatClient.sendMessage(
            model: model,
            messages: messages,
            tools: tools,
            creationRequest: AiCreationRequest.none,
          ),
        );
        final endedAt = DateTime.now();
        final durationMs = endedAt.difference(startedAt).inMilliseconds;
        _forgetProxyFailure(network.selected?.url);
        await _recordDispatch(
          context: recordContext,
          success: true,
          durationMs: durationMs,
          providerId: provider.id,
          modelId: backend.modelId,
          usage: result.usage,
          route: network,
          outboundBytes:
              result.reply.length + (result.rawResponse?.length ?? 0),
          attempt: attempt + 1,
        );
        return AiModelProxyDispatchResult(
          reply: result.reply,
          exposedModel: exposedModel,
          backend: backend,
          durationMs: durationMs,
          usage: result.usage,
          reasoningContent: result.reasoningContent,
          toolCalls: result.toolCalls,
          rawResponse: result.rawResponse,
        );
      } catch (error) {
        lastError = error;
        await _recordFailedAttempt(
          context: recordContext,
          startedAt: startedAt,
          providerId: provider.id,
          modelId: backend.modelId,
          error: error,
          route: network,
          attempt: attempt,
        );
        if (await _shouldStopAfterFailure(
          error: error,
          retryState: retryState,
          route: network,
          directRouteFallback: directRouteFallback,
          backend: backend,
          backendPlan: backendPlan,
          retryPolicy: settings.retryPolicy,
          attempt: attempt,
          maxAttempts: maxAttempts,
        )) {
          break;
        }
      } finally {
        routedClient?.dispose();
      }
    }
    _throwDispatchFailure(lastError);
  }

  Future<AiModelProxyStreamDispatch> dispatchStream({
    required String exposedModel,
    required List<AiChatTurn> messages,
    Map<String, Object?> request = const <String, Object?>{},
    Map<String, String> headers = const <String, String>{},
    String requestPath = '',
    int inboundBytes = 0,
  }) async {
    final (
      :tools,
      :settings,
      :maxAttempts,
      :recordContext,
      :backendPlan,
      :retryState,
    ) = _prepareDispatch(
      exposedModel: exposedModel,
      messages: messages,
      request: request,
      headers: headers,
      requestPath: requestPath,
      inboundBytes: inboundBytes,
      stream: true,
    );
    Object? lastError;
    for (
      var attempt = 0;
      attempt < maxAttempts + _kAiModelProxyDirectFallbackAttempts;
      attempt++
    ) {
      final directFallback = attempt >= maxAttempts;
      if (directFallback && !retryState.directFallbackEnabled) break;
      final prepared = await _prepareBackendAttempt(
        backendPlan: backendPlan,
        directFallback: directFallback,
        request: request,
        headers: headers,
        context: recordContext,
        settings: settings,
        attempt: attempt,
        maxAttempts: maxAttempts,
      );
      if (prepared == null) continue;
      final (:backend, :provider, :model) = prepared;
      final startedAt = DateTime.now();
      var network = _emptyDirectProxyRoute;
      _RoutedChatClient? routedClient;
      var directRouteFallback = directFallback;
      try {
        network = await _resolveAttemptRoute(
          model.baseUrl,
          retryState,
          directFallback: directFallback,
        );
        directRouteFallback = retryState.recordRoute(
          network,
          directFallback: directFallback,
        );
        routedClient = _usesDefaultChatClient
            ? await _createRoutedChatClient(network)
            : null;
        final chatClient = routedClient?.service ?? _chatClient;
        final response = await _runTracedRequest(
          context: recordContext,
          route: network,
          body: () => chatClient.sendMessageStream(
            model: model,
            messages: messages,
            tools: tools,
            creationRequest: AiCreationRequest.none,
          ),
        );
        unawaited(
          response.result
              .then<void>(
                (result) async {
                  _forgetProxyFailure(network.selected?.url);
                  const cancelledError = AiModelProxyException(499, '流式请求已取消。');
                  await _recordDispatch(
                    context: recordContext,
                    success: !result.wasCancelled,
                    durationMs: DateTime.now()
                        .difference(startedAt)
                        .inMilliseconds,
                    providerId: provider.id,
                    modelId: backend.modelId,
                    error: result.wasCancelled ? cancelledError.message : null,
                    failure: result.wasCancelled ? cancelledError : null,
                    usage: result.usage,
                    route: network,
                    outboundBytes: result.reply.length,
                    attempt: attempt + 1,
                  );
                },
                onError: (Object error, StackTrace stack) async {
                  if (_classifyBackendFailure(error) ==
                      _BackendFailureKind.transport) {
                    final failedEndpoint = network.selected?.url;
                    if (failedEndpoint != null) {
                      _rememberProxyFailure(failedEndpoint);
                    }
                  }
                  await _recordFailedAttempt(
                    context: recordContext,
                    startedAt: startedAt,
                    providerId: provider.id,
                    modelId: backend.modelId,
                    error: error,
                    route: network,
                    attempt: attempt,
                  );
                },
              )
              .whenComplete(() {
                routedClient?.dispose();
              }),
        );
        return AiModelProxyStreamDispatch(
          response: response,
          exposedModel: exposedModel,
          backend: backend,
        );
      } catch (error) {
        lastError = error;
        await _recordFailedAttempt(
          context: recordContext,
          startedAt: startedAt,
          providerId: provider.id,
          modelId: backend.modelId,
          error: error,
          route: network,
          attempt: attempt,
        );
        routedClient?.dispose();
        if (await _shouldStopAfterFailure(
          error: error,
          retryState: retryState,
          route: network,
          directRouteFallback: directRouteFallback,
          backend: backend,
          backendPlan: backendPlan,
          retryPolicy: settings.retryPolicy,
          attempt: attempt,
          maxAttempts: maxAttempts,
        )) {
          break;
        }
      }
    }
    _throwDispatchFailure(lastError);
  }

  Future<void> _recordFailedAttempt({
    required _ProxyRequestContext context,
    required DateTime startedAt,
    required String providerId,
    required String modelId,
    required Object error,
    required _ProxyNetworkRoute route,
    required int attempt,
  }) {
    return _recordDispatch(
      context: context,
      success: false,
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      providerId: providerId,
      modelId: modelId,
      error: '$error',
      failure: error,
      route: route,
      attempt: attempt + 1,
    );
  }

  Future<void> _recordDispatch({
    required _ProxyRequestContext context,
    required bool success,
    required int durationMs,
    required String providerId,
    required String modelId,
    String? error,
    Object? failure,
    AiTokenUsage? usage,
    _ProxyNetworkRoute route = _emptyDirectProxyRoute,
    int outboundBytes = 0,
    int attempt = 1,
  }) {
    final statusCode = success
        ? 200
        : (_backendErrorStatusCode(failure) ?? (error == null ? 0 : 502));
    return controller.recordRequest(
      AiModelProxyRequestRecord.capture(
        success: success,
        tokens: usage?.totalTokens ?? 0,
        durationMs: durationMs,
        providerId: providerId,
        modelId: modelId,
        apiStyle: context.apiStyle,
        error: error,
        clientIp: _clientIp(context.headers),
        clientPort: _clientPort(context.headers),
        clientUserAgent: _clientUserAgent(context.headers),
        clientProcessId: _headerValue(context.headers, 'x-openhand-client-pid'),
        clientProcessName: _headerValue(
          context.headers,
          'x-openhand-client-name',
        ),
        clientServiceName: _headerValue(
          context.headers,
          'x-openhand-client-service',
        ),
        clientMacAddress: _headerValue(
          context.headers,
          'x-openhand-client-mac',
        ),
        proxyMode: route.mode,
        proxyEndpoint: route.endpoint,
        remoteHost: route.remoteHost,
        remotePort: route.remotePort,
        exposedModel: context.exposedModel,
        requestPath: context.requestPath,
        promptTokens: usage?.promptTokens ?? 0,
        completionTokens: usage?.completionTokens ?? 0,
        inboundBytes: context.inboundBytes,
        outboundBytes: outboundBytes,
        statusCode: statusCode,
        attempt: attempt,
        stream: context.stream,
      ),
    );
  }

  static String _headerValue(Map<String, String> headers, String key) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != key) continue;
      final value = entry.value.trim();
      return value.length > 256 ? value.substring(0, 256) : value;
    }
    return '';
  }

  static Map<String, Object?> _usageTraceMetadata({
    required String exposedModel,
    required String proxyMode,
    required String proxyEndpoint,
    required String remoteHost,
    required String remotePort,
    required Map<String, String> headers,
  }) {
    return <String, Object?>{
      'exposed_model': exposedModel,
      'proxy_mode': proxyMode,
      'proxy_endpoint': proxyEndpoint,
      'remote_host': remoteHost,
      'remote_port': remotePort,
      'client_ip': _clientIp(headers),
      'client_port': _clientPort(headers),
      'client_user_agent': _clientUserAgent(headers),
      'source_ip': _clientIp(headers),
      'source_port': _clientPort(headers),
      'source_kind': 'proxy_client',
      'client_metadata_source': 'client_declared',
      'client_process_pid': _headerValue(headers, 'x-openhand-client-pid'),
      'client_process_name': _headerValue(headers, 'x-openhand-client-name'),
      'client_service_name': _headerValue(headers, 'x-openhand-client-service'),
      'client_mac_address': _headerValue(headers, 'x-openhand-client-mac'),
    };
  }

  void _validateRequest(
    String exposedModel,
    List<AiChatTurn> messages,
    Map<String, String> headers,
  ) {
    if (!controller.authorize(headers)) {
      throw const AiModelProxyException(401, 'API 鉴权失败。');
    }
    if (!controller.isExposedModelEnabled(exposedModel)) {
      throw const AiModelProxyException(404, '模型不存在。');
    }
    final totalCharacters = messages.fold<int>(
      0,
      (sum, item) => sum + item.content.length,
    );
    final estimatedTokens = totalCharacters <= 0
        ? 0
        : math.max(1, (totalCharacters + 3) ~/ 4);
    if (!controller.consumeRateLimit(
      tokens: estimatedTokens,
      clientIp: _clientIp(headers),
      userAgent: _clientUserAgent(headers),
    )) {
      throw const AiModelProxyException(429, '请求超过当前限流阈值。');
    }
  }

  _ProxyDispatchSetup _prepareDispatch({
    required String exposedModel,
    required List<AiChatTurn> messages,
    required Map<String, Object?> request,
    required Map<String, String> headers,
    required String requestPath,
    required int inboundBytes,
    required bool stream,
  }) {
    _validateRequest(exposedModel, messages, headers);
    final settings = controller.settings;
    return (
      tools: _parseToolsForRequest(request),
      settings: settings,
      maxAttempts: _configuredAttemptCount(settings),
      recordContext: (
        exposedModel: exposedModel,
        headers: headers,
        apiStyle: settings.apiStyle.id,
        requestPath: requestPath,
        inboundBytes: inboundBytes,
        stream: stream,
      ),
      backendPlan: _ProxyBackendAttemptPlan(
        controller: controller,
        exposedModel: exposedModel,
        policy: settings.retryPolicy,
        affinityKey: _backendAffinityKey(headers),
      ),
      retryState: _ProxyRetryState(),
    );
  }

  static int _configuredAttemptCount(AiModelProxySettings settings) {
    if (settings.retryPolicy == AiModelProxyRetryPolicy.failFast) return 1;
    return settings.retryCount.clamp(1, 10).toInt() + 1;
  }

  static bool _canFailover(
    AiModelProxySettings settings,
    int attempt,
    int maxAttempts,
  ) =>
      settings.retryPolicy == AiModelProxyRetryPolicy.retryAndFailover &&
      attempt + 1 < maxAttempts;

  Future<_PreparedProxyBackend?> _prepareBackendAttempt({
    required _ProxyBackendAttemptPlan backendPlan,
    required bool directFallback,
    required Map<String, Object?> request,
    required Map<String, String> headers,
    required _ProxyRequestContext context,
    required AiModelProxySettings settings,
    required int attempt,
    required int maxAttempts,
  }) async {
    final backend = backendPlan.select(directFallback: directFallback);
    if (backend == null) {
      throw const AiModelProxyException(404, '没有可用的后备模型。');
    }

    Future<_PreparedProxyBackend?> reject(
      String providerId,
      AiModelProxyException failure,
    ) async {
      await _recordDispatch(
        context: context,
        success: false,
        durationMs: 0,
        providerId: providerId,
        modelId: backend.modelId,
        error: failure.message,
        failure: failure,
        attempt: attempt + 1,
      );
      if (_canFailover(settings, attempt, maxAttempts)) {
        backendPlan.exclude(backend);
        return null;
      }
      throw failure;
    }

    final provider = modelsProvider()
        .where((item) => item.id == backend.providerId)
        .firstOrNull;
    if (provider == null) {
      return reject(
        backend.providerId,
        const AiModelProxyException(404, '后备模型提供商不存在。'),
      );
    }
    final model = _modelForRequest(
      provider.copyWith(modelId: backend.modelId),
      request,
      headers: headers,
    );
    if (controller.isSelfProxyBaseUrl(model.baseUrl)) {
      return reject(
        provider.id,
        const AiModelProxyException(400, '后备模型端点不能指向当前中转站，否则会形成请求循环。'),
      );
    }
    return (backend: backend, provider: provider, model: model);
  }

  T _runTracedRequest<T>({
    required _ProxyRequestContext context,
    required _ProxyNetworkRoute route,
    required T Function() body,
  }) {
    return AiUsageTraceContext.runDerived(
      surface: 'service',
      source: AiUsageSource.modelProxy,
      operation: 'proxy_request',
      metadata: _usageTraceMetadata(
        exposedModel: context.exposedModel,
        proxyMode: route.mode,
        proxyEndpoint: route.endpoint,
        remoteHost: route.remoteHost,
        remotePort: route.remotePort,
        headers: context.headers,
      ),
      body: body,
    );
  }

  Future<bool> _shouldStopAfterFailure({
    required Object error,
    required _ProxyRetryState retryState,
    required _ProxyNetworkRoute route,
    required bool directRouteFallback,
    required AiModelProxyBackend backend,
    required _ProxyBackendAttemptPlan backendPlan,
    required AiModelProxyRetryPolicy retryPolicy,
    required int attempt,
    required int maxAttempts,
  }) async {
    final failureKind = _classifyBackendFailure(error);
    retryState.recordFailure(
      failureKind: failureKind,
      route: route,
      directRouteFallback: directRouteFallback,
      backend: backend,
      backendPlan: backendPlan,
      rememberProxyFailure: _rememberProxyFailure,
    );
    if (retryState.shouldStop(
      failureKind: failureKind,
      directRouteFallback: directRouteFallback,
      retryPolicy: retryPolicy,
    )) {
      return true;
    }
    if (failureKind == _BackendFailureKind.backend &&
        attempt + 1 < maxAttempts) {
      await _waitBeforeBackendRetry(attempt);
    }
    return false;
  }

  /// 将暴露 API 的本次请求参数注入底层模型配置。协议适配器会在生成
  /// 请求体时合并 operation extras，因此不会污染持久化的模型设置。
  AiModelConfig _modelForRequest(
    AiModelConfig model,
    Map<String, Object?> request, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final style = controller.settings.apiStyle;
    if (style == AiModelProxyApiStyle.claude &&
        model.apiDialect == AiApiDialect.openAiCompat) {
      final rawMaxTokens =
          request['max_tokens'] ??
          request['max_output_tokens'] ??
          request['max_completion_tokens'];
      if (rawMaxTokens is num && rawMaxTokens.isFinite && rawMaxTokens > 0) {
        final maxOutput =
            model.profileFor(model.modelId).maxOutputLength ?? (1 << 20);
        model = model.copyWith(
          maxTokens: rawMaxTokens.toInt().clamp(1, maxOutput).toInt(),
        );
      }
    }
    if (style == AiModelProxyApiStyle.openAiChatCompletions &&
        model.apiDialect == AiApiDialect.openAiCompat) {
      final capabilities = <AiApiFamily, String>{
        ...model.capabilityOverrides,
        AiApiFamily.responses: 'disabled',
      };
      model = model.copyWith(capabilityOverrides: capabilities);
    }
    final extras = _requestBodyExtras(request, model);
    if (style == AiModelProxyApiStyle.openAiChatCompletions &&
        model.apiDialect == AiApiDialect.openAiCompat &&
        request['messages'] is List) {
      extras['messages'] = request['messages'];
    } else if (style == AiModelProxyApiStyle.openAiResponses &&
        model.apiDialect == AiApiDialect.openAiCompat &&
        '${model.capabilityStatusFor(AiApiFamily.responses)}'.toLowerCase() !=
            'disabled' &&
        request['input'] != null) {
      extras['input'] = request['input'];
    } else if (style == AiModelProxyApiStyle.claude &&
        model.apiDialect == AiApiDialect.anthropicNative &&
        request['messages'] is List) {
      extras['messages'] = request['messages'];
    } else if (style == AiModelProxyApiStyle.gemini &&
        model.apiDialect == AiApiDialect.geminiNative &&
        request['contents'] is List) {
      extras['contents'] = request['contents'];
    }
    final forwardedHeaders = _forwardedRequestHeaders(
      headers,
      model.apiDialect,
    );
    if (extras.isEmpty && forwardedHeaders.isEmpty) return model;
    final operationExtras = <String, Object?>{...model.operationExtras};
    final global = stringKeyedMapFromValue(operationExtras['global']);
    final existingBody = stringKeyedMapFromValue(global['body']);
    global['body'] = <String, Object?>{...existingBody, ...extras};
    if (forwardedHeaders.isNotEmpty) {
      global['headers'] = <String, String>{
        ..._stringMap(global['headers']),
        ...forwardedHeaders,
      };
    }
    operationExtras['global'] = global;
    return model.copyWith(operationExtras: operationExtras);
  }

  static Map<String, String> _forwardedRequestHeaders(
    Map<String, String> headers,
    AiApiDialect dialect,
  ) {
    final allowed = switch (dialect) {
      AiApiDialect.openAiCompat => const <String>{
        'openai-beta',
        'openai-organization',
        'openai-project',
      },
      AiApiDialect.anthropicNative => const <String>{
        'anthropic-version',
        'anthropic-beta',
      },
      AiApiDialect.geminiNative => const <String>{
        'x-goog-user-project',
        'x-goog-api-client',
      },
    };
    return <String, String>{
      for (final entry in headers.entries)
        if (allowed.contains(entry.key.toLowerCase()) &&
            entry.value.trim().isNotEmpty)
          entry.key.toLowerCase(): entry.value.trim(),
    };
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in value.entries) '${entry.key}': '${entry.value}',
    };
  }

  Map<String, Object?> _requestBodyExtras(
    Map<String, Object?> request,
    AiModelConfig model,
  ) {
    final extras = <String, Object?>{};
    final style = controller.settings.apiStyle;
    if (style == AiModelProxyApiStyle.gemini) {
      final generationConfig = stringKeyedMapFromValue(
        request['generationConfig'],
      );
      if (generationConfig.isNotEmpty) {
        extras['generationConfig'] = generationConfig;
      }
      for (final entry in request.entries) {
        if (entry.key == 'model' ||
            entry.key == 'contents' ||
            entry.key == 'generationConfig' ||
            entry.key == 'stream' ||
            entry.key == 'tools') {
          continue;
        }
        extras[entry.key] = entry.value;
      }
    } else {
      for (final entry in request.entries) {
        if (entry.key == 'model' ||
            entry.key == 'messages' ||
            entry.key == 'input' ||
            entry.key == 'stream' ||
            entry.key == 'contents' ||
            entry.key == 'tools') {
          continue;
        }
        extras[entry.key] = entry.value;
      }
    }
    final preservedTools = _preservedRawTools(request['tools'], model);
    if (preservedTools != null && preservedTools.isNotEmpty) {
      extras['tools'] = preservedTools;
    }
    _normalizeCrossProtocolExtras(extras, request, model);
    if (_choiceType(request['tool_choice']) == 'none') {
      extras.remove('tools');
    }
    return extras;
  }

  void _normalizeCrossProtocolExtras(
    Map<String, Object?> extras,
    Map<String, Object?> request,
    AiModelConfig model,
  ) {
    final inboundStyle = controller.settings.apiStyle;
    switch (model.apiDialect) {
      case AiApiDialect.openAiCompat:
        if (inboundStyle == AiModelProxyApiStyle.claude) {
          for (final key in const <String>[
            'system',
            'thinking',
            'output_config',
            'top_k',
            'max_tokens',
            'max_completion_tokens',
            'max_output_tokens',
          ]) {
            extras.remove(key);
          }
          final stop = _stopValue(request['stop_sequences']);
          if (stop != null) extras['stop'] = stop;
          extras.remove('stop_sequences');
          final choice = _openAiToolChoice(request['tool_choice']);
          if (choice == null) {
            extras.remove('tool_choice');
          } else {
            extras['tool_choice'] = choice;
          }
        }
      case AiApiDialect.anthropicNative:
        if (inboundStyle != AiModelProxyApiStyle.claude) {
          for (final key in const <String>[
            'instructions',
            'response_format',
            'reasoning_effort',
            'max_completion_tokens',
            'stream_options',
          ]) {
            extras.remove(key);
          }
          final maxOutputTokens = request['max_output_tokens'];
          if (maxOutputTokens is num) {
            extras['max_tokens'] = maxOutputTokens;
          }
          extras.remove('max_output_tokens');
          final stop = _stopValue(request['stop']);
          if (stop != null) extras['stop_sequences'] = stop;
          extras.remove('stop');
          final choice = _claudeToolChoice(request['tool_choice']);
          if (choice == null) {
            extras.remove('tool_choice');
          } else {
            extras['tool_choice'] = choice;
          }
        }
      case AiApiDialect.geminiNative:
        extras.remove('tool_choice');
        final generationConfig = stringKeyedMapFromValue(
          extras['generationConfig'],
        );
        final temperature = request['temperature'];
        final topP = request['top_p'];
        final maxTokens =
            request['max_tokens'] ??
            request['max_completion_tokens'] ??
            request['max_output_tokens'];
        if (temperature is num) generationConfig['temperature'] = temperature;
        if (topP is num) generationConfig['topP'] = topP;
        if (maxTokens is num) generationConfig['maxOutputTokens'] = maxTokens;
        final stop = _stopValue(request['stop'] ?? request['stop_sequences']);
        if (stop is String) {
          generationConfig['stopSequences'] = <String>[stop];
        } else if (stop is List) {
          generationConfig['stopSequences'] = stop;
        }
        if (generationConfig.isNotEmpty) {
          extras['generationConfig'] = generationConfig;
        }
        for (final key in const <String>[
          'temperature',
          'top_p',
          'max_tokens',
          'max_completion_tokens',
          'max_output_tokens',
          'stop',
          'stop_sequences',
          'response_format',
          'reasoning_effort',
        ]) {
          extras.remove(key);
        }
    }
  }

  static Object? _stopValue(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List) {
      final values = value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .take(4)
          .toList(growable: false);
      if (values.isNotEmpty) return values;
    }
    return null;
  }

  static String? _choiceType(Object? value) {
    if (value is String) return value.trim().toLowerCase();
    if (value is Map) {
      return '${stringKeyedMapFromValue(value)['type'] ?? ''}'
          .trim()
          .toLowerCase();
    }
    return null;
  }

  static Object? _openAiToolChoice(Object? value) {
    final type = _choiceType(value);
    return switch (type) {
      'auto' => 'auto',
      'none' => 'none',
      'required' || 'any' => 'required',
      _ => null,
    };
  }

  static Map<String, Object?>? _claudeToolChoice(Object? value) {
    final type = _choiceType(value);
    return switch (type) {
      'auto' => const <String, Object?>{'type': 'auto'},
      'required' || 'any' => const <String, Object?>{'type': 'any'},
      'tool' => () {
        final map = stringKeyedMapFromValue(value);
        final name = map['name'];
        return name is String && name.trim().isNotEmpty
            ? <String, Object?>{'type': 'tool', 'name': name.trim()}
            : null;
      }(),
      _ => null,
    };
  }

  List<AiToolDefinition> _parseTools(Map<String, Object?> request) {
    final raw = request['tools'];
    if (raw is! List) return const <AiToolDefinition>[];
    if (raw.length > _maxProxyTools) {
      throw const AiModelProxyException(400, '工具数量超过限制。');
    }
    final tools = <AiToolDefinition>[];
    final names = <String>{};
    void addTool(Object? value) {
      if (value is! Map) return;
      final item = Map<String, Object?>.from(value);
      final function = item['function'] is Map
          ? Map<String, Object?>.from(item['function'] as Map)
          : item;
      final nameValue = function['name'];
      if (nameValue is! String) return;
      final name = nameValue.trim();
      if (name.isEmpty ||
          name.length > _maxProxyToolNameLength ||
          !names.add(name)) {
        return;
      }
      final parameters = stringKeyedMapFromValue(
        function['parameters'] ??
            function['input_schema'] ??
            function['parametersJson'],
      );
      tools.add(
        AiToolDefinition(
          name: name,
          description: _boundedToolDescription(function['description']),
          parameters: parameters.isEmpty
              ? const <String, Object?>{'type': 'object'}
              : parameters,
          strict: function['strict'] is bool
              ? function['strict'] as bool
              : null,
        ),
      );
    }

    for (final item in raw.take(_maxProxyTools)) {
      if (item is Map && item['functionDeclarations'] is List) {
        final declarations = item['functionDeclarations'] as List;
        for (final declaration in declarations.take(
          _maxProxyTools - tools.length,
        )) {
          addTool(declaration);
        }
      } else {
        addTool(item);
      }
    }
    return List<AiToolDefinition>.unmodifiable(tools);
  }

  List<AiToolDefinition> _parseToolsForRequest(Map<String, Object?> request) {
    if (_choiceType(request['tool_choice']) == 'none') {
      return const <AiToolDefinition>[];
    }
    return _parseTools(request);
  }

  static String _boundedToolDescription(Object? value) {
    if (value is! String) return '';
    final description = value.trim();
    return clipTextByCodeUnits(
      description,
      _maxProxyToolDescriptionLength,
      suffix: '',
    );
  }

  /// 入站协议和上游协议可能不同，原样工具只能按后备模型方言透传。
  List<Object?>? _preservedRawTools(Object? raw, AiModelConfig model) {
    if (raw is! List || raw.isEmpty || raw.length > _maxProxyTools) {
      return null;
    }
    final maps = raw.whereType<Map>().toList(growable: false);
    if (maps.length != raw.length) return null;
    return switch (model.apiDialect) {
      AiApiDialect.openAiCompat => _isOpenAiToolList(maps) ? raw : null,
      AiApiDialect.anthropicNative => _isClaudeToolList(maps) ? raw : null,
      AiApiDialect.geminiNative => _isGeminiToolList(maps) ? raw : null,
    };
  }

  bool _isOpenAiToolList(List<Map> tools) {
    return tools.every((raw) {
      final map = stringKeyedMapFromValue(raw);
      final type = map['type'];
      if (type is! String || type.trim().isEmpty || type.length > 64) {
        return false;
      }
      if (type == 'function') {
        final name = stringKeyedMapFromValue(map['function'])['name'];
        return name is String &&
            name.trim().isNotEmpty &&
            name.trim().length <= _maxProxyToolNameLength;
      }
      return true;
    });
  }

  bool _isClaudeToolList(List<Map> tools) {
    return tools.every((raw) {
      final map = stringKeyedMapFromValue(raw);
      final name = map['name'];
      return name is String &&
          name.trim().isNotEmpty &&
          name.trim().length <= _maxProxyToolNameLength &&
          stringKeyedMapFromValue(map['input_schema']).isNotEmpty;
    });
  }

  bool _isGeminiToolList(List<Map> tools) {
    return tools.every((raw) {
      final declarations = stringKeyedMapFromValue(raw)['functionDeclarations'];
      return declarations is List && declarations.isNotEmpty;
    });
  }

  static int? _backendErrorStatusCode(Object? error) {
    if (error is AiChatException) return error.statusCode;
    if (error is AiModelProxyException) return error.statusCode;
    return null;
  }

  static _BackendFailureKind _classifyBackendFailure(Object error) {
    if (error is AiChatException) {
      final statusCode = error.statusCode;
      if (statusCode != null) {
        final rawResponse = error.telemetry?.rawResponse ?? error.message;
        if (statusCode == HttpStatus.notFound &&
            AiTransportDiagnosticMessages.relayModelAvailabilityReason(
                  rawResponse,
                ) !=
                null) {
          return _BackendFailureKind.backend;
        }
        return _isRetryableHttpStatus(statusCode)
            ? _BackendFailureKind.backend
            : _BackendFailureKind.terminal;
      }
      if (error.telemetry != null && error.telemetry?.rawResponse == null) {
        return _BackendFailureKind.transport;
      }
      return AiTransportDiagnosticMessages.isRetryableTransportError(error)
          ? _BackendFailureKind.transport
          : _BackendFailureKind.terminal;
    }
    if (error is AiModelProxyException) {
      return error.statusCode >= 500
          ? _BackendFailureKind.transport
          : _isRetryableHttpStatus(error.statusCode)
          ? _BackendFailureKind.backend
          : _BackendFailureKind.terminal;
    }
    if (error is TimeoutException ||
        error is HandshakeException ||
        error is TlsException ||
        error is SocketException ||
        error is http.ClientException) {
      return _BackendFailureKind.transport;
    }
    return _BackendFailureKind.terminal;
  }

  static bool _isRetryableHttpStatus(int statusCode) =>
      isHttpTransientRetryableStatus(statusCode) ||
      statusCode == kHttpConflictStatusCode ||
      isHttpServerErrorStatus(statusCode);

  static Future<void> _waitBeforeBackendRetry(int attempt) async {
    await delayUntilCancelled(
      exponentialBackoffDuration(
        attempt: attempt + 1,
        base: _kAiModelProxyRetryDelayBase,
        cap: _kAiModelProxyRetryDelayCap,
      ),
    );
  }

  static String _backendErrorMessage(Object? error) {
    if (error is AiChatException) return error.message;
    if (error is AiModelProxyException) return error.message;
    return '$error';
  }

  static Never _throwDispatchFailure(Object? error) {
    final statusCode = _backendErrorStatusCode(error);
    if (statusCode != null) {
      throw AiModelProxyException(statusCode, _backendErrorMessage(error));
    }
    throw AiModelProxyException(502, '后备模型请求失败：$error');
  }

  Future<_ProxyNetworkRoute> _resolveAttemptRoute(
    String baseUrl,
    _ProxyRetryState retryState, {
    required bool directFallback,
  }) {
    return _resolveNetworkRoute(
      Uri.tryParse(baseUrl),
      excludedProxyEndpoints: <String>{
        ...retryState.failedProxyEndpoints,
        ..._coolingProxyEndpoints(),
      },
      preferredProxyEndpoint: retryState.preferredProxyEndpoint,
      directOnly: directFallback,
    );
  }

  Future<_ProxyNetworkRoute> _resolveNetworkRoute(
    Uri? target, {
    Set<String> excludedProxyEndpoints = const <String>{},
    AiExposureProxyEndpoint? preferredProxyEndpoint,
    bool directOnly = false,
  }) async {
    final remoteHost = target?.host ?? '';
    final remotePort = target == null
        ? ''
        : '${target.port > 0
              ? target.port
              : target.scheme == 'https'
              ? 443
              : 80}';
    final configuration = controller.networkProxyConfiguration;
    if (directOnly ||
        configuration == null ||
        !configuration.enabled ||
        (configuration.bypassLocal && _isLocalTarget(remoteHost))) {
      return (
        mode: _kProxyRouteDirect,
        endpoint: '',
        remoteHost: remoteHost,
        remotePort: remotePort,
        selected: null,
      );
    }
    if (configuration.mode == AiExposureProxyMode.system) {
      await SystemProxyResolver.instance.initialize();
      final snapshot = SystemProxyResolver.instance.resolveRuntimeRoute();
      final endpoint = snapshot.httpsProxy ?? snapshot.httpProxy;
      return (
        mode: endpoint == null ? _kProxyRouteDirect : _kProxyRouteSystem,
        endpoint: endpoint == null ? '' : _maskProxyEndpoint(endpoint),
        remoteHost: remoteHost,
        remotePort: remotePort,
        selected: null,
      );
    }
    AiExposureProxyEndpoint? endpoint;
    final preferredUrl = preferredProxyEndpoint?.url;
    if (preferredUrl != null &&
        !excludedProxyEndpoints.contains(preferredUrl)) {
      for (final candidate in configuration.activeEndpoints) {
        if (candidate.url == preferredUrl) {
          endpoint = candidate;
          break;
        }
      }
    }
    endpoint ??= controller.resolveProxyEndpoint(
      targetHost: remoteHost,
      excludedUrls: excludedProxyEndpoints,
    );
    return (
      mode: endpoint == null ? _kProxyRouteDirect : _kProxyRoutePool,
      endpoint: endpoint == null ? '' : endpoint.maskedUrl,
      remoteHost: remoteHost,
      remotePort: remotePort,
      selected: endpoint,
    );
  }

  static bool _isLocalTarget(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized.isEmpty || isLoopbackHost(normalized);
  }

  Future<_RoutedChatClient?> _createRoutedChatClient(
    _ProxyNetworkRoute route,
  ) async {
    if (route.mode == _kProxyRouteSystem) {
      final transport = SystemProxyResolver.instance.createHttpClient(
        userAgent: _kAiModelProxyUserAgent,
      );
      return _RoutedChatClient(
        service: AiChatService(client: transport),
        transport: transport,
      );
    }
    if (route.mode != _kProxyRoutePool) {
      final raw = HttpClient()
        ..connectionTimeout = _kAiModelProxyConnectionTimeout;
      raw.findProxy = (_) => 'DIRECT';
      raw.userAgent = _kAiModelProxyUserAgent;
      final transport = IOClient(raw);
      return _RoutedChatClient(
        service: AiChatService(client: transport),
        transport: transport,
      );
    }
    final endpoint = route.selected;
    final uri = endpoint == null ? null : Uri.tryParse(endpoint.url);
    if (uri == null || uri.host.isEmpty || !isValidTcpPort(uri.port)) {
      throw const AiModelProxyException(502, '中转代理地址无效，无法建立后备模型连接。');
    }
    final raw = HttpClient()
      ..connectionTimeout = _kAiModelProxyConnectionTimeout;
    raw.userAgent = _kAiModelProxyUserAgent;
    try {
      configureAiExposureProxyHttpClient(raw, uri);
    } on Object {
      raw.close(force: true);
      throw const AiModelProxyException(502, '中转代理配置无效。');
    }
    final transport = IOClient(raw);
    return _RoutedChatClient(
      service: AiChatService(client: transport),
      transport: transport,
    );
  }

  void dispose() {
    if (_usesDefaultChatClient) _chatClient.dispose();
    _proxyFailureCooldowns.clear();
  }

  Set<String> _coolingProxyEndpoints() {
    final now = DateTime.now();
    _proxyFailureCooldowns.removeWhere(
      (_, expiresAt) => !expiresAt.isAfter(now),
    );
    return _proxyFailureCooldowns.keys.toSet();
  }

  void _rememberProxyFailure(String url) {
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    _coolingProxyEndpoints();
    _proxyFailureCooldowns.remove(normalized);
    if (_proxyFailureCooldowns.length >= _kAiModelProxyFailureCooldownLimit) {
      _proxyFailureCooldowns.remove(_proxyFailureCooldowns.keys.first);
    }
    _proxyFailureCooldowns[normalized] = DateTime.now().add(
      _kAiModelProxyFailureCooldown,
    );
  }

  void _forgetProxyFailure(String? url) {
    if (url != null) _proxyFailureCooldowns.remove(url);
  }
}

enum _BackendFailureKind { terminal, backend, transport }

/// 统一维护同步与流式中转的代理降级状态，避免两条链路出现重试语义漂移。
class _ProxyRetryState {
  final Set<String> failedProxyEndpoints = <String>{};
  bool directFallbackEnabled = false;
  int _directFallbackAttempts = 0;
  AiExposureProxyEndpoint? preferredProxyEndpoint;

  bool isDirectRouteFallback(
    _ProxyNetworkRoute route, {
    required bool directFallback,
  }) {
    return directFallback ||
        (route.mode == _kProxyRouteDirect && failedProxyEndpoints.isNotEmpty);
  }

  bool recordRoute(_ProxyNetworkRoute route, {required bool directFallback}) {
    if (route.mode == _kProxyRoutePool) preferredProxyEndpoint = route.selected;
    final usesDirectFallback = isDirectRouteFallback(
      route,
      directFallback: directFallback,
    );
    if (usesDirectFallback) _directFallbackAttempts++;
    return usesDirectFallback;
  }

  void recordFailure({
    required _BackendFailureKind failureKind,
    required _ProxyNetworkRoute route,
    required bool directRouteFallback,
    required AiModelProxyBackend backend,
    required _ProxyBackendAttemptPlan backendPlan,
    required void Function(String endpoint) rememberProxyFailure,
  }) {
    if (failureKind == _BackendFailureKind.transport) {
      backendPlan.prepareDirectFallback(backend);
      final failedEndpoint = route.selected?.url;
      if (failedEndpoint != null) {
        failedProxyEndpoints.add(failedEndpoint);
        rememberProxyFailure(failedEndpoint);
      }
      preferredProxyEndpoint = null;
      if (!directRouteFallback && route.mode == _kProxyRoutePool) {
        directFallbackEnabled = true;
      }
    } else if (failureKind == _BackendFailureKind.backend) {
      backendPlan.recordBackendFailure(backend);
    }
  }

  bool shouldStop({
    required _BackendFailureKind failureKind,
    required bool directRouteFallback,
    required AiModelProxyRetryPolicy retryPolicy,
  }) {
    return failureKind == _BackendFailureKind.terminal ||
        (directRouteFallback &&
            _directFallbackAttempts >= _kAiModelProxyDirectFallbackAttempts) ||
        (retryPolicy == AiModelProxyRetryPolicy.failFast &&
            failureKind != _BackendFailureKind.transport);
  }
}

/// 为单次入口请求维护后备模型重试策略，避免同步与流式链路各自解释策略。
class _ProxyBackendAttemptPlan {
  _ProxyBackendAttemptPlan({
    required this.controller,
    required this.exposedModel,
    required this.policy,
    required this.affinityKey,
  });

  final AiModelProxyController controller;
  final String exposedModel;
  final AiModelProxyRetryPolicy policy;
  final String affinityKey;
  final Set<AiModelProxyBackend> _failedBackends = <AiModelProxyBackend>{};
  AiModelProxyBackend? _fixedBackend;
  AiModelProxyBackend? _directFallbackBackend;
  AiModelProxyBackend? _lastFailedBackend;

  AiModelProxyBackend? select({required bool directFallback}) {
    if (directFallback && _directFallbackBackend != null) {
      return _directFallbackBackend;
    }
    if (policy == AiModelProxyRetryPolicy.retrySame && _fixedBackend != null) {
      return _fixedBackend;
    }
    var backend = controller.resolveBackend(
      exposedModel,
      excludedBackends: policy == AiModelProxyRetryPolicy.retryAndFailover
          ? _failedBackends
          : const <AiModelProxyBackend>{},
      affinityKey: affinityKey,
    );
    if (backend == null && _failedBackends.isNotEmpty) {
      final lastFailed = _lastFailedBackend;
      _failedBackends.clear();
      if (lastFailed != null) _failedBackends.add(lastFailed);
      backend = controller.resolveBackend(
        exposedModel,
        excludedBackends: _failedBackends,
        affinityKey: affinityKey,
      );
      if (backend == null) {
        _failedBackends.clear();
        backend = controller.resolveBackend(
          exposedModel,
          affinityKey: affinityKey,
        );
      }
    }
    if (policy == AiModelProxyRetryPolicy.retrySame) {
      _fixedBackend = backend;
    }
    return backend;
  }

  void recordBackendFailure(AiModelProxyBackend backend) {
    if (policy == AiModelProxyRetryPolicy.retryAndFailover) {
      exclude(backend);
    }
  }

  void prepareDirectFallback(AiModelProxyBackend backend) =>
      _directFallbackBackend = backend;

  void exclude(AiModelProxyBackend backend) {
    _failedBackends.add(backend);
    _lastFailedBackend = backend;
  }
}

class _RoutedChatClient {
  const _RoutedChatClient({required this.service, required this.transport});

  final AiChatService service;
  final http.Client transport;

  void dispose() {
    service.dispose();
    transport.close();
  }
}

String _headerValue(Map<String, String> headers, List<String> names) {
  for (final name in names) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name && entry.value.trim().isNotEmpty) {
        final value = entry.value.split(',').first.trim();
        return value.length <= 512 ? value : value.substring(0, 512);
      }
    }
  }
  return '';
}

String _clientIp(Map<String, String> headers) {
  final hasServerAddress = headers.keys.any(
    (key) => key.toLowerCase() == 'x-client-ip',
  );
  if (hasServerAddress) {
    return _headerValue(headers, const ['x-client-ip']);
  }
  return _headerValue(headers, const ['x-forwarded-for', 'x-real-ip']);
}

String _clientUserAgent(Map<String, String> headers) =>
    _headerValue(headers, const ['user-agent']);

String _backendAffinityKey(Map<String, String> headers) {
  final clientIp = _clientIp(headers);
  return clientIp.isEmpty ? _clientUserAgent(headers) : clientIp;
}

String _clientPort(Map<String, String> headers) {
  final hasServerPort = headers.keys.any(
    (key) => key.toLowerCase() == 'x-client-port',
  );
  if (hasServerPort) return _headerValue(headers, const ['x-client-port']);
  return _headerValue(headers, const ['x-forwarded-port']);
}

String _maskProxyEndpoint(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.userInfo.isEmpty) return value;
  return uri.replace(userInfo: '******').toString();
}

class AiModelProxyException implements Exception {
  const AiModelProxyException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}
