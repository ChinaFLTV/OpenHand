import 'ai_model_config.dart';
import 'ai_session.dart';
import 'ai_session_message.dart';
import 'ai_session_runtime_context.dart';

bool isInputCacheModelSelectionLocked({
  required bool inputCacheEnabled,
  required Iterable<AiSessionMessage> messages,
}) {
  if (!inputCacheEnabled) return false;
  var hasValidUserMessage = false;
  for (final message in messages) {
    if (!hasValidUserMessage) {
      hasValidUserMessage =
          message.kind == AiSessionMessageKind.user &&
          message.isTranscriptRenderable;
      continue;
    }
    if (message.isAiSideConversationMessage && message.isTranscriptRenderable) {
      return true;
    }
  }
  return false;
}

bool isInputCacheModelSelectionLockedForSession({
  required bool inputCacheEnabled,
  required AiSession session,
  Iterable<AiSessionMessage> candidateMessages = const <AiSessionMessage>[],
}) {
  if (!inputCacheEnabled) return false;
  if (isInputCacheModelSelectionLocked(
        inputCacheEnabled: true,
        messages: session.messages,
      ) ||
      isInputCacheModelSelectionLocked(
        inputCacheEnabled: true,
        messages: candidateMessages,
      )) {
    return true;
  }
  if (session.hasCompleteMessages) return false;

  // 会话懒加载期间使用持久化统计兜底，避免输入区先于消息窗口解锁。
  final statistics = session.statistics;
  return statistics.userMessageCount > 0 &&
      (statistics.assistantMessageCount > 0 ||
          statistics.toolMessageCount > 0 ||
          (statistics.totalCompletionTokens ?? 0) > 0);
}

enum AiInputCacheControlStrategy {
  disabled('disabled'),
  providerDisabled('provider_disabled'),
  explicitCacheControl('explicit_cache_control'),
  automaticProviderCache('automatic_provider_cache');

  const AiInputCacheControlStrategy(this.storageValue);

  final String storageValue;
}

class AiInputCachePolicy {
  const AiInputCachePolicy({
    required this.strategy,
    required this.globalEnabled,
    required this.explicitControlSupported,
    required this.explicitControlEnabled,
  });

  factory AiInputCachePolicy.resolve({
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
  }) {
    final globalEnabled = runtimeContext.aiInputCacheEnabled;
    final explicitControlSupported = model.supportsExplicitPromptCacheControl;
    final explicitControlEnabled = model.effectiveExplicitPromptCacheEnabled;
    if (!globalEnabled) {
      return AiInputCachePolicy(
        strategy: AiInputCacheControlStrategy.disabled,
        globalEnabled: false,
        explicitControlSupported: explicitControlSupported,
        explicitControlEnabled: explicitControlEnabled,
      );
    }
    if (!explicitControlSupported) {
      return const AiInputCachePolicy(
        strategy: AiInputCacheControlStrategy.automaticProviderCache,
        globalEnabled: true,
        explicitControlSupported: false,
        explicitControlEnabled: false,
      );
    }
    if (!explicitControlEnabled) {
      return const AiInputCachePolicy(
        strategy: AiInputCacheControlStrategy.providerDisabled,
        globalEnabled: true,
        explicitControlSupported: true,
        explicitControlEnabled: false,
      );
    }
    return const AiInputCachePolicy(
      strategy: AiInputCacheControlStrategy.explicitCacheControl,
      globalEnabled: true,
      explicitControlSupported: true,
      explicitControlEnabled: true,
    );
  }

  final AiInputCacheControlStrategy strategy;
  final bool globalEnabled;
  final bool explicitControlSupported;
  final bool explicitControlEnabled;

  bool get stablePromptPrefixEnabled => globalEnabled;

  bool get injectsExplicitCacheControl =>
      strategy == AiInputCacheControlStrategy.explicitCacheControl;

  bool get usesAutomaticProviderCache =>
      strategy == AiInputCacheControlStrategy.automaticProviderCache;

  bool get emitsProtocolCacheHints =>
      injectsExplicitCacheControl || usesAutomaticProviderCache;

  bool get defersBackgroundRequests => false;
}
