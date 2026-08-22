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
  });

  final String reply;
  final String exposedModel;
  final AiModelProxyBackend backend;
  final int durationMs;
  final AiTokenUsage? usage;
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

  Future<AiModelProxyDispatchResult> dispatch({
    required String exposedModel,
    required List<AiChatTurn> messages,
    Map<String, String> headers = const <String, String>{},
  }) async {
    if (!controller.authorize(headers)) {
      throw const AiModelProxyException(401, 'API 鉴权失败。');
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
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final backend = controller.resolveBackend(exposedModel);
      if (backend == null) {
        throw const AiModelProxyException(404, '没有可用的后备模型。');
      }
      final provider = modelsProvider()
          .where((item) => item.id == backend.providerId)
          .firstOrNull;
      if (provider == null) {
        lastError = StateError('后备模型提供商不存在。');
        continue;
      }
      final model = provider.copyWith(modelId: backend.modelId);
      final startedAt = DateTime.now();
      final network = await _resolveNetworkRoute(Uri.tryParse(model.baseUrl));
      final routedClient = _usesDefaultChatClient
          ? await _createRoutedChatClient(network)
          : null;
      final chatClient = routedClient?.service ?? _chatClient;
      try {
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
        if (settings.retryPolicy == AiModelProxyRetryPolicy.failFast) break;
      } finally {
        routedClient?.dispose();
      }
    }
    throw AiModelProxyException(502, '后备模型请求失败：$lastError');
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
  _resolveNetworkRoute(Uri? target) async {
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
    final endpoint = controller.resolveProxyEndpoint(targetHost: remoteHost);
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
      final transport = IOClient(HttpClient()..findProxy = (_) => 'DIRECT');
      return _RoutedChatClient(
        service: AiChatService(client: transport),
        transport: transport,
      );
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
        return null;
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
