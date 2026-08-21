import '../../ai/index.dart';
import '../ai_model_proxy_controller.dart';
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
  }) : _chatClient = chatClient ?? AiChatService();

  final AiModelProxyController controller;
  final List<AiModelConfig> Function() modelsProvider;
  final AiChatClient _chatClient;

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
      try {
        final result = await _chatClient.sendMessage(
          model: model,
          messages: messages,
          creationRequest: AiCreationRequest.none,
          allowResponsesFallback:
              settings.apiStyle == AiModelProxyApiStyle.openAiResponses,
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
        );
        if (settings.retryPolicy == AiModelProxyRetryPolicy.failFast) break;
      }
    }
    throw AiModelProxyException(502, '后备模型请求失败：$lastError');
  }

  void dispose() => _chatClient.dispose();
}

class AiModelProxyException implements Exception {
  const AiModelProxyException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}
