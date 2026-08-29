import '../../model/ai_model_config.dart';
import '../../model/ai_session.dart';

class AiSessionModelReference {
  const AiSessionModelReference({
    required this.providerConfigId,
    required this.modelId,
  });

  final String providerConfigId;
  final String modelId;
}

AiSessionModelReference? aiSessionModelReference(AiSession session) {
  final providerConfigId = session.lastUsedModelId?.trim() ?? '';
  final modelId = session.lastUsedModelLabel?.trim() ?? '';
  if (providerConfigId.isNotEmpty && modelId.isNotEmpty) {
    return AiSessionModelReference(
      providerConfigId: providerConfigId,
      modelId: modelId,
    );
  }

  for (var index = session.messages.length - 1; index >= 0; index -= 1) {
    final message = session.messages[index];
    if (message.isDeleted) continue;
    final messageProviderConfigId = message.modelId?.trim() ?? '';
    final messageModelId = message.modelLabel?.trim() ?? '';
    if (messageProviderConfigId.isNotEmpty && messageModelId.isNotEmpty) {
      return AiSessionModelReference(
        providerConfigId: messageProviderConfigId,
        modelId: messageModelId,
      );
    }
  }
  return null;
}

AiModelConfig? resolveAiSessionModel({
  required AiSession session,
  required List<AiModelConfig> availableModels,
  AiModelConfig? fallbackForUnboundSession,
}) {
  final reference = aiSessionModelReference(session);
  if (reference == null) {
    final hasPartialReference =
        session.lastUsedModelId?.trim().isNotEmpty == true ||
        session.lastUsedModelLabel?.trim().isNotEmpty == true;
    return hasPartialReference || session.messageTotalCount > 0
        ? null
        : fallbackForUnboundSession;
  }

  for (final provider in availableModels) {
    if (provider.id == reference.providerConfigId) {
      if (!provider.allModelIds.contains(reference.modelId)) return null;
      return provider.modelId == reference.modelId
          ? provider
          : provider.copyWith(modelId: reference.modelId);
    }
  }

  final compatibleProviders = availableModels
      .where((provider) => provider.allModelIds.contains(reference.modelId))
      .toList(growable: false);
  if (compatibleProviders.isEmpty) return null;

  final fallback = fallbackForUnboundSession;
  final provider = fallback == null
      ? compatibleProviders.first
      : compatibleProviders.firstWhere(
          (item) => item.id == fallback.id,
          orElse: () => compatibleProviders.first,
        );
  return provider.modelId == reference.modelId
      ? provider
      : provider.copyWith(modelId: reference.modelId);
}
