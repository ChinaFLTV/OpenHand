import 'ai_model_config.dart';
import 'ai_session_runtime_context.dart';

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

  bool get defersBackgroundRequests =>
      stablePromptPrefixEnabled && usesAutomaticProviderCache;
}
