import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../app/support/system_proxy.dart';
import '../../ai/index.dart';
import '../ai_model_proxy_controller.dart';
import '../model/ai_exposure_models.dart';
import '../model/ai_model_proxy_models.dart';

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

  /// 返回中转站当前已配置的暴露模型，供 `/v1/models` 端点直接使用。
  Map<String, Object?> buildModelsResponse() =>
      controller.buildModelsResponse();

  Future<AiModelProxyDispatchResult> dispatch({
    required String exposedModel,
    required List<AiChatTurn> messages,
    Map<String, Object?> request = const <String, Object?>{},
    Map<String, String> headers = const <String, String>{},
  }) async {
    if (!controller.authorize(headers)) {
      throw const AiModelProxyException(401, 'API 鉴权失败。');
    }
    if (!controller.isExposedModelEnabled(exposedModel)) {
      throw const AiModelProxyException(404, '模型不存在。');
    }
    if (!controller.consumeRateLimit(
      tokens: messages.fold<int>(
        0,
        (sum, item) => sum + item.content.length ~/ 4,
      ),
    )) {
      throw const AiModelProxyException(429, '请求超过当前限流阈值。');
    }
    final settings = controller.settings;
    final maxAttempts = settings.retryPolicy == AiModelProxyRetryPolicy.failFast
        ? 1
        : settings.retryCount.clamp(1, 10).toInt() +
              (settings.retryPolicy == AiModelProxyRetryPolicy.retryAndFailover
                  ? 1
                  : 0);
    Object? lastError;
    final failedProxyEndpoints = <String>{};
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final backend = controller.resolveBackend(exposedModel);
      if (backend == null) {
        throw const AiModelProxyException(404, '没有可用的后备模型。');
      }
      final provider = modelsProvider()
          .where((item) => item.id == backend.providerId)
          .firstOrNull;
      if (provider == null) {
        lastError = const AiModelProxyException(404, '后备模型提供商不存在。');
        await controller.recordRequest(
          success: false,
          tokens: 0,
          durationMs: 0,
          providerId: backend.providerId,
          modelId: backend.modelId,
          apiStyle: settings.apiStyle.id,
          error: '$lastError',
        );
        break;
      }
      final model = _modelForRequest(
        provider.copyWith(modelId: backend.modelId),
        request,
        headers: headers,
      );
      if (controller.isSelfProxyBaseUrl(model.baseUrl)) {
        lastError = const AiModelProxyException(
          400,
          '后备模型端点不能指向当前中转站，否则会形成请求循环。',
        );
        await controller.recordRequest(
          success: false,
          tokens: 0,
          durationMs: 0,
          providerId: provider.id,
          modelId: backend.modelId,
          apiStyle: settings.apiStyle.id,
          error: lastError.toString(),
        );
        break;
      }
      final tools = _parseTools(request);
      final startedAt = DateTime.now();
      var network = (
        mode: 'direct',
        endpoint: '',
        remoteHost: '',
        remotePort: '',
        selected: null as AiExposureProxyEndpoint?,
      );
      _RoutedChatClient? routedClient;
      try {
        network = await _resolveNetworkRoute(
          Uri.tryParse(model.baseUrl),
          excludedProxyEndpoints: failedProxyEndpoints,
        );
        routedClient = _usesDefaultChatClient
            ? await _createRoutedChatClient(network)
            : null;
        final chatClient = routedClient?.service ?? _chatClient;
        final result = await AiUsageTraceContext.runDerived(
          surface: 'service',
          source: AiUsageSource.modelProxy,
          operation: 'proxy_request',
          metadata: <String, Object?>{
            'exposed_model': exposedModel,
            'proxy_mode': network.mode,
            'proxy_endpoint': network.endpoint,
            'remote_host': network.remoteHost,
            'remote_port': network.remotePort,
            'client_ip': _headerValue(headers, const <String>[
              'x-forwarded-for',
              'x-real-ip',
              'x-client-ip',
            ]),
            'client_port': _headerValue(headers, const <String>[
              'x-forwarded-port',
              'x-client-port',
            ]),
          },
          body: () => chatClient.sendMessage(
            model: model,
            messages: messages,
            tools: tools,
            creationRequest: AiCreationRequest.none,
            allowResponsesFallback:
                settings.apiStyle == AiModelProxyApiStyle.openAiResponses,
          ),
        );
        final endedAt = DateTime.now();
        final durationMs = endedAt.difference(startedAt).inMilliseconds;
        await controller.recordRequest(
          success: true,
          tokens: result.usage?.totalTokens ?? 0,
          durationMs: durationMs,
          providerId: provider.id,
          modelId: backend.modelId,
          apiStyle: settings.apiStyle.id,
          clientIp: _headerValue(headers, const <String>[
            'x-forwarded-for',
            'x-real-ip',
            'x-client-ip',
          ]),
          clientPort: _headerValue(headers, const <String>[
            'x-forwarded-port',
            'x-client-port',
          ]),
          proxyMode: network.mode,
          proxyEndpoint: network.endpoint,
          remoteHost: network.remoteHost,
          remotePort: network.remotePort,
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
        await controller.recordRequest(
          success: false,
          tokens: 0,
          durationMs: DateTime.now().difference(startedAt).inMilliseconds,
          providerId: provider.id,
          modelId: backend.modelId,
          apiStyle: settings.apiStyle.id,
          error: '$error',
          clientIp: _headerValue(headers, const <String>[
            'x-forwarded-for',
            'x-real-ip',
            'x-client-ip',
          ]),
          clientPort: _headerValue(headers, const <String>[
            'x-forwarded-port',
            'x-client-port',
          ]),
          proxyMode: network.mode,
          proxyEndpoint: network.endpoint,
          remoteHost: network.remoteHost,
          remotePort: network.remotePort,
        );
        final retryable = _isRetryableBackendError(error);
        if (retryable) {
          final failedEndpoint = network.selected?.url;
          if (failedEndpoint != null) failedProxyEndpoints.add(failedEndpoint);
        }
        if (settings.retryPolicy == AiModelProxyRetryPolicy.failFast ||
            !retryable) {
          break;
        }
      } finally {
        routedClient?.dispose();
      }
    }
    final statusCode = _backendErrorStatusCode(lastError);
    if (statusCode != null) {
      throw AiModelProxyException(statusCode, _backendErrorMessage(lastError));
    }
    throw AiModelProxyException(502, '后备模型请求失败：$lastError');
  }

  Future<AiModelProxyStreamDispatch> dispatchStream({
    required String exposedModel,
    required List<AiChatTurn> messages,
    Map<String, Object?> request = const <String, Object?>{},
    Map<String, String> headers = const <String, String>{},
  }) async {
    if (!controller.authorize(headers)) {
      throw const AiModelProxyException(401, 'API 鉴权失败。');
    }
    if (!controller.isExposedModelEnabled(exposedModel)) {
      throw const AiModelProxyException(404, '模型不存在。');
    }
    if (!controller.consumeRateLimit(
      tokens: messages.fold<int>(
        0,
        (sum, item) => sum + item.content.length ~/ 4,
      ),
    )) {
      throw const AiModelProxyException(429, '请求超过当前限流阈值。');
    }
    final settings = controller.settings;
    final maxAttempts = settings.retryPolicy == AiModelProxyRetryPolicy.failFast
        ? 1
        : settings.retryCount.clamp(1, 10).toInt() +
              (settings.retryPolicy == AiModelProxyRetryPolicy.retryAndFailover
                  ? 1
                  : 0);
    Object? lastError;
    final failedProxyEndpoints = <String>{};
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final backend = controller.resolveBackend(exposedModel);
      if (backend == null) {
        lastError = const AiModelProxyException(404, '没有可用的后备模型。');
        break;
      }
      final provider = modelsProvider()
          .where((item) => item.id == backend.providerId)
          .firstOrNull;
      if (provider == null) {
        lastError = const AiModelProxyException(404, '后备模型提供商不存在。');
        await controller.recordRequest(
          success: false,
          tokens: 0,
          durationMs: 0,
          providerId: backend.providerId,
          modelId: backend.modelId,
          apiStyle: settings.apiStyle.id,
          error: lastError.toString(),
        );
        break;
      }
      final model = _modelForRequest(
        provider.copyWith(modelId: backend.modelId),
        request,
        headers: headers,
      );
      final startedAt = DateTime.now();
      var network = (
        mode: 'direct',
        endpoint: '',
        remoteHost: '',
        remotePort: '',
        selected: null as AiExposureProxyEndpoint?,
      );
      _RoutedChatClient? routedClient;
      try {
        if (controller.isSelfProxyBaseUrl(model.baseUrl)) {
          throw const AiModelProxyException(400, '后备模型端点不能指向当前中转站，否则会形成请求循环。');
        }
        network = await _resolveNetworkRoute(
          Uri.tryParse(model.baseUrl),
          excludedProxyEndpoints: failedProxyEndpoints,
        );
        routedClient = _usesDefaultChatClient
            ? await _createRoutedChatClient(network)
            : null;
        final chatClient = routedClient?.service ?? _chatClient;
        final response = await chatClient.sendMessageStream(
          model: model,
          messages: messages,
          tools: _parseTools(request),
          creationRequest: AiCreationRequest.none,
        );
        unawaited(
          response.result
              .then<void>(
                (result) async {
                  await controller.recordRequest(
                    success: !result.wasCancelled,
                    tokens: result.usage?.totalTokens ?? 0,
                    durationMs: DateTime.now()
                        .difference(startedAt)
                        .inMilliseconds,
                    providerId: provider.id,
                    modelId: backend.modelId,
                    apiStyle: controller.settings.apiStyle.id,
                    clientIp: _headerValue(headers, const <String>[
                      'x-forwarded-for',
                      'x-real-ip',
                      'x-client-ip',
                    ]),
                    clientPort: _headerValue(headers, const <String>[
                      'x-forwarded-port',
                      'x-client-port',
                    ]),
                    proxyMode: network.mode,
                    proxyEndpoint: network.endpoint,
                    remoteHost: network.remoteHost,
                    remotePort: network.remotePort,
                  );
                },
                onError: (Object error, StackTrace stack) async {
                  await controller.recordRequest(
                    success: false,
                    tokens: 0,
                    durationMs: DateTime.now()
                        .difference(startedAt)
                        .inMilliseconds,
                    providerId: provider.id,
                    modelId: backend.modelId,
                    apiStyle: controller.settings.apiStyle.id,
                    error: '$error',
                    clientIp: _headerValue(headers, const <String>[
                      'x-forwarded-for',
                      'x-real-ip',
                      'x-client-ip',
                    ]),
                    clientPort: _headerValue(headers, const <String>[
                      'x-forwarded-port',
                      'x-client-port',
                    ]),
                    proxyMode: network.mode,
                    proxyEndpoint: network.endpoint,
                    remoteHost: network.remoteHost,
                    remotePort: network.remotePort,
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
        await controller.recordRequest(
          success: false,
          tokens: 0,
          durationMs: DateTime.now().difference(startedAt).inMilliseconds,
          providerId: provider.id,
          modelId: backend.modelId,
          apiStyle: settings.apiStyle.id,
          error: '$error',
          proxyMode: network.mode,
          proxyEndpoint: network.endpoint,
          remoteHost: network.remoteHost,
          remotePort: network.remotePort,
        );
        routedClient?.dispose();
        final retryable = _isRetryableBackendError(error);
        if (retryable) {
          final failedEndpoint = network.selected?.url;
          if (failedEndpoint != null) failedProxyEndpoints.add(failedEndpoint);
        }
        if (settings.retryPolicy == AiModelProxyRetryPolicy.failFast ||
            !retryable) {
          break;
        }
      }
    }
    final statusCode = _backendErrorStatusCode(lastError);
    if (statusCode != null) {
      throw AiModelProxyException(statusCode, _backendErrorMessage(lastError));
    }
    throw AiModelProxyException(502, '后备模型请求失败：$lastError');
  }

  /// 将暴露 API 的本次请求参数注入底层模型配置。协议适配器会在生成
  /// 请求体时合并 operation extras，因此不会污染持久化的模型设置。
  AiModelConfig _modelForRequest(
    AiModelConfig model,
    Map<String, Object?> request, {
    Map<String, String> headers = const <String, String>{},
  }) {
    if (controller.settings.apiStyle != AiModelProxyApiStyle.openAiResponses &&
        model.apiDialect == AiApiDialect.openAiCompat) {
      final capabilities = <AiApiFamily, String>{
        ...model.capabilityOverrides,
        AiApiFamily.responses: 'disabled',
      };
      model = model.copyWith(capabilityOverrides: capabilities);
    }
    final extras = _requestBodyExtras(request);
    final style = controller.settings.apiStyle;
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
    final forwardedHeaders = _forwardedRequestHeaders(headers);
    if (extras.isEmpty && forwardedHeaders.isEmpty) return model;
    final operationExtras = <String, Object?>{...model.operationExtras};
    final global = _map(operationExtras['global']);
    final existingBody = _map(global['body']);
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
  ) {
    const allowed = <String>{
      'anthropic-version',
      'anthropic-beta',
      'openai-beta',
      'openai-organization',
      'openai-project',
      'x-goog-user-project',
      'x-goog-api-client',
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

  Map<String, Object?> _requestBodyExtras(Map<String, Object?> request) {
    final extras = <String, Object?>{};
    final style = controller.settings.apiStyle;
    if (style == AiModelProxyApiStyle.gemini) {
      final generationConfig = _map(request['generationConfig']);
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
    final rawTools = request['tools'];
    if (rawTools is List &&
        rawTools.isNotEmpty &&
        (_parseTools(request).isEmpty || _shouldPreserveRawTools(rawTools))) {
      extras['tools'] = rawTools;
    }
    return extras;
  }

  List<AiToolDefinition> _parseTools(Map<String, Object?> request) {
    final raw = request['tools'];
    if (raw is! List) return const <AiToolDefinition>[];
    final tools = <AiToolDefinition>[];
    final names = <String>{};
    void addTool(Object? value) {
      if (value is! Map) return;
      final item = Map<String, Object?>.from(value);
      final function = item['function'] is Map
          ? Map<String, Object?>.from(item['function'] as Map)
          : item;
      final name = '${function['name'] ?? ''}'.trim();
      if (name.isEmpty || !names.add(name)) return;
      final parameters = _map(
        function['parameters'] ??
            function['input_schema'] ??
            function['parametersJson'],
      );
      tools.add(
        AiToolDefinition(
          name: name,
          description: '${function['description'] ?? ''}',
          parameters: parameters.isEmpty
              ? const <String, Object?>{'type': 'object'}
              : parameters,
          strict: function['strict'] is bool
              ? function['strict'] as bool
              : null,
        ),
      );
    }

    for (final item in raw) {
      if (item is Map && item['functionDeclarations'] is List) {
        for (final declaration in item['functionDeclarations'] as List) {
          addTool(declaration);
        }
      } else {
        addTool(item);
      }
    }
    return List<AiToolDefinition>.unmodifiable(tools);
  }

  bool _containsUnsupportedOpenAiTool(List<Object?> rawTools) {
    final style = controller.settings.apiStyle;
    if (style != AiModelProxyApiStyle.openAiChatCompletions &&
        style != AiModelProxyApiStyle.openAiResponses) {
      return false;
    }
    return rawTools.any((item) {
      if (item is! Map) return true;
      final map = Map<String, Object?>.from(item);
      if (_map(map['function']).isNotEmpty) return false;
      return '${map['type'] ?? ''}' != 'function';
    });
  }

  bool _shouldPreserveRawTools(List<Object?> rawTools) {
    final style = controller.settings.apiStyle;
    if (style == AiModelProxyApiStyle.openAiChatCompletions ||
        style == AiModelProxyApiStyle.openAiResponses) {
      return _containsUnsupportedOpenAiTool(rawTools);
    }
    if (style == AiModelProxyApiStyle.gemini) {
      return rawTools.any(
        (item) => item is Map && item['functionDeclarations'] is List,
      );
    }
    if (style == AiModelProxyApiStyle.claude) {
      return rawTools.every((item) {
        if (item is! Map) return false;
        final map = Map<String, Object?>.from(item);
        return map['name'] != null || map['input_schema'] != null;
      });
    }
    return false;
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    return <String, Object?>{};
  }

  static int? _backendErrorStatusCode(Object? error) {
    if (error is AiChatException) return error.statusCode;
    if (error is AiModelProxyException) return error.statusCode;
    return null;
  }

  static bool _isRetryableBackendError(Object error) {
    if (error is AiModelProxyException) return false;
    final statusCode = _backendErrorStatusCode(error);
    if (statusCode == null) return true;
    return statusCode == 408 ||
        statusCode == 409 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  static String _backendErrorMessage(Object? error) {
    if (error is AiChatException) return error.message;
    if (error is AiModelProxyException) return error.message;
    return '$error';
  }

  Future<
    ({
      String mode,
      String endpoint,
      String remoteHost,
      String remotePort,
      AiExposureProxyEndpoint? selected,
    })
  >
  _resolveNetworkRoute(
    Uri? target, {
    Set<String> excludedProxyEndpoints = const <String>{},
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
    if (configuration == null || !configuration.enabled) {
      return (
        mode: 'direct',
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
        mode: endpoint == null ? 'direct' : 'system',
        endpoint: endpoint == null ? '' : _maskProxyEndpoint(endpoint),
        remoteHost: remoteHost,
        remotePort: remotePort,
        selected: null,
      );
    }
    final endpoint = controller.resolveProxyEndpoint(
      targetHost: remoteHost,
      excludedUrls: excludedProxyEndpoints,
    );
    return (
      mode: endpoint == null ? 'direct' : 'pool',
      endpoint: endpoint == null ? '' : endpoint.maskedUrl,
      remoteHost: remoteHost,
      remotePort: remotePort,
      selected: endpoint,
    );
  }

  Future<_RoutedChatClient?> _createRoutedChatClient(
    ({
      String mode,
      String endpoint,
      String remoteHost,
      String remotePort,
      AiExposureProxyEndpoint? selected,
    })
    route,
  ) async {
    if (route.mode == 'system') {
      final transport = SystemProxyResolver.instance.createHttpClient();
      return _RoutedChatClient(
        service: AiChatService(client: transport),
        transport: transport,
      );
    }
    if (route.mode != 'pool') {
      final transport = IOClient(HttpClient()..findProxy = (_) => 'DIRECT');
      return _RoutedChatClient(
        service: AiChatService(client: transport),
        transport: transport,
      );
    }
    final endpoint = route.selected;
    final uri = endpoint == null ? null : Uri.tryParse(endpoint.url);
    if (uri == null || uri.host.isEmpty || uri.port <= 0) {
      throw const AiModelProxyException(502, '中转代理地址无效，无法建立后备模型连接。');
    }
    final raw = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..findProxy = (_) => 'PROXY ${uri.host}:${uri.port}';
    if (uri.userInfo.isNotEmpty) {
      final parts = uri.userInfo.split(':');
      try {
        raw.addProxyCredentials(
          uri.host,
          uri.port,
          'Basic',
          HttpClientBasicCredentials(
            Uri.decodeComponent(parts.first),
            parts.length > 1
                ? Uri.decodeComponent(parts.sublist(1).join(':'))
                : '',
          ),
        );
      } on Object {
        raw.close(force: true);
        throw const AiModelProxyException(502, '中转代理凭据无效。');
      }
    }
    final transport = IOClient(raw);
    return _RoutedChatClient(
      service: AiChatService(client: transport),
      transport: transport,
    );
  }

  void dispose() => _chatClient.dispose();
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
        return entry.value.split(',').first.trim();
      }
    }
  }
  return '';
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
