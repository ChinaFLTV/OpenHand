import '../../model/ai_model_config.dart';

class AiTitleModelResolver {
  const AiTitleModelResolver._();

  static List<AiModelConfig> buildFallbackChain({
    required List<AiModelConfig> models,
    required AiModelConfig currentModel,
  }) {
    final candidates = <AiModelConfig>[];
    final seen = <String>{};

    void addCandidate(AiModelConfig? candidate) {
      if (candidate == null || !supportsTextTitleGeneration(candidate)) {
        return;
      }
      final key = _candidateKey(candidate);
      if (seen.add(key)) {
        candidates.add(candidate);
      }
    }

    final sourceProvider =
        _providerById(models, currentModel.id) ??
        currentModel.copyWith(availableModelIds: currentModel.allModelIds);
    addCandidate(currentModel);
    addCandidate(_providerDefaultTitleModel(sourceProvider));

    final globalProvider = _globalDefaultTitleProvider(models);
    addCandidate(_globalDefaultTitleModel(globalProvider));

    return candidates.toList(growable: false);
  }

  static AiModelConfig? resolveDefault({
    required List<AiModelConfig> models,
    required AiModelConfig? currentModel,
  }) {
    if (currentModel != null) {
      final chain = buildFallbackChain(
        models: models,
        currentModel: currentModel,
      );
      return chain.isNotEmpty ? chain.first : null;
    }
    final global = _globalDefaultTitleModel(
      _globalDefaultTitleProvider(models),
    );
    if (global != null && supportsTextTitleGeneration(global)) {
      return global;
    }
    for (final model in models) {
      final active = model.modelId.trim();
      if (active.isEmpty) continue;
      final candidate = model.copyWith(modelId: active);
      if (supportsTextTitleGeneration(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static bool supportsTextTitleGeneration(AiModelConfig model) {
    final modelId = model.modelId.trim();
    if (modelId.isEmpty) {
      return false;
    }
    final profile = model.profileFor(modelId);
    final explicitModalities = profile.supportedModalities;
    if (explicitModalities.isNotEmpty) {
      return explicitModalities.contains(AiModelModality.text);
    }

    final architecture = profile.architecture;
    final modality = architecture?.modality?.trim().toLowerCase() ?? '';
    if (modality.isNotEmpty) {
      if (modality.contains('text')) {
        return true;
      }
      if (_nonTextModalityMarkers.any((marker) => modality.contains(marker))) {
        return false;
      }
    }

    final outputModalities =
        architecture?.outputModalities
            .map((item) => item.trim().toLowerCase())
            .where((item) => item.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    if (outputModalities.isNotEmpty) {
      return outputModalities.any((item) => item.contains('text'));
    }
    return true;
  }

  static AiModelConfig normalizeProviderTitleDefaults(AiModelConfig model) {
    final activeModelId = model.modelId.trim();
    final defaultTitleModelId = model.defaultTitleModelId.trim();
    return model.copyWith(
      modelId: activeModelId,
      defaultTitleModelId: defaultTitleModelId,
      availableModelIds: AiModelConfig.normalizeModelIds(<String>[
        ...model.availableModelIds,
        if (activeModelId.isNotEmpty) activeModelId,
        if (defaultTitleModelId.isNotEmpty) defaultTitleModelId,
      ]),
    );
  }

  static List<AiModelConfig> normalizeProviders(
    Iterable<AiModelConfig> models,
  ) {
    var hasGlobalDefault = false;
    final normalized = <AiModelConfig>[];
    for (final model in models) {
      var next = normalizeProviderTitleDefaults(model);
      if (next.isGlobalDefaultTitleModel) {
        if (hasGlobalDefault) {
          next = next.copyWith(isGlobalDefaultTitleModel: false);
        } else {
          hasGlobalDefault = true;
        }
      }
      normalized.add(next);
    }
    return normalized.toList(growable: false);
  }

  static AiModelConfig? _providerById(
    List<AiModelConfig> models,
    String providerId,
  ) {
    final normalizedProviderId = providerId.trim();
    if (normalizedProviderId.isEmpty) return null;
    for (final model in models) {
      if (model.id == normalizedProviderId) {
        return model;
      }
    }
    return null;
  }

  static AiModelConfig? _providerDefaultTitleModel(AiModelConfig provider) {
    final modelId = provider.defaultTitleModelId.trim();
    if (modelId.isEmpty) return null;
    return provider.copyWith(
      modelId: modelId,
      availableModelIds: AiModelConfig.normalizeModelIds(<String>[
        ...provider.availableModelIds,
        modelId,
      ]),
    );
  }

  static AiModelConfig? _globalDefaultTitleProvider(
    List<AiModelConfig> models,
  ) {
    for (final model in models) {
      if (model.isGlobalDefaultTitleModel) {
        return model;
      }
    }
    return null;
  }

  static AiModelConfig? _globalDefaultTitleModel(AiModelConfig? provider) {
    if (provider == null) return null;
    final modelId = provider.defaultTitleModelId.trim().isNotEmpty
        ? provider.defaultTitleModelId.trim()
        : provider.modelId.trim();
    if (modelId.isEmpty) return null;
    return provider.copyWith(
      modelId: modelId,
      availableModelIds: AiModelConfig.normalizeModelIds(<String>[
        ...provider.availableModelIds,
        modelId,
      ]),
    );
  }

  static String _candidateKey(AiModelConfig model) {
    return '${model.id.trim()}::${model.modelId.trim()}';
  }

  static const Set<String> _nonTextModalityMarkers = <String>{
    'image',
    'audio',
    'video',
    'speech',
    'embedding',
  };
}
