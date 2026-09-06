import '../../../../shared/util/input_value_parsing.dart';
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

    addCandidate(_globalDefaultTitleModel(models));

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
    final global = _globalDefaultTitleModel(models);
    if (global != null && supportsTextTitleGeneration(global)) {
      return global;
    }
    for (final model in models) {
      final active = nullIfBlank(model.modelId);
      if (active == null) continue;
      final candidate = model.copyWith(modelId: active);
      if (supportsTextTitleGeneration(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static bool supportsTextTitleGeneration(AiModelConfig model) {
    final modelId = nullIfBlank(model.modelId);
    if (modelId == null) {
      return false;
    }
    final profile = model.profileFor(modelId);
    final explicitModalities = profile.supportedModalities;
    if (explicitModalities.isNotEmpty) {
      return explicitModalities.contains(AiModelModality.text);
    }

    final architecture = profile.architecture;
    final modality = optionalLowercaseStringFromValue(architecture?.modality);
    if (modality != null) {
      if (modality.contains('text')) {
        return true;
      }
      if (_nonTextModalityMarkers.any(modality.contains)) {
        return false;
      }
    }

    final outputModalities =
        architecture?.outputModalities
            .map(optionalLowercaseStringFromValue)
            .whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    if (outputModalities.isNotEmpty) {
      return outputModalities.any((item) => item.contains('text'));
    }
    return true;
  }

  static AiModelConfig normalizeProviderTitleDefaults(AiModelConfig model) {
    final activeModelId = nullIfBlank(model.modelId) ?? '';
    final defaultTitleModelId = nullIfBlank(model.defaultTitleModelId) ?? '';
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
    var hasProfileGlobalDefault = false;
    final staged = <AiModelConfig>[];
    for (final model in models) {
      var next = normalizeProviderTitleDefaults(model);
      final visibleModelIds = next.allModelIds.toSet();
      final profiles = <String, AiModelProfile>{};
      for (final entry in next.modelProfiles.entries) {
        final modelId = nullIfBlank(entry.key);
        if (modelId == null) continue;
        var profile = entry.value;
        if (profile.isGlobalDefaultTitleModel) {
          if (!visibleModelIds.contains(modelId) || hasProfileGlobalDefault) {
            profile = profile.copyWith(isGlobalDefaultTitleModel: false);
          } else {
            hasProfileGlobalDefault = true;
          }
        }
        if (profile.hasUserOverrides) {
          profiles[modelId] = profile;
        }
      }
      next = next.copyWith(modelProfiles: profiles);
      staged.add(next);
    }

    var hasLegacyGlobalDefault = false;
    final normalized = <AiModelConfig>[];
    for (var next in staged) {
      if (next.isGlobalDefaultTitleModel) {
        if (hasProfileGlobalDefault || hasLegacyGlobalDefault) {
          next = next.copyWith(isGlobalDefaultTitleModel: false);
        } else {
          hasLegacyGlobalDefault = true;
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
    final normalizedProviderId = nullIfBlank(providerId);
    if (normalizedProviderId == null) return null;
    for (final model in models) {
      if (model.id == normalizedProviderId) {
        return model;
      }
    }
    return null;
  }

  static AiModelConfig? _providerDefaultTitleModel(AiModelConfig provider) {
    final modelId = nullIfBlank(provider.defaultTitleModelId);
    if (modelId == null) return null;
    return provider.copyWith(
      modelId: modelId,
      availableModelIds: AiModelConfig.normalizeModelIds(<String>[
        ...provider.availableModelIds,
        modelId,
      ]),
    );
  }

  static AiModelConfig? _globalDefaultTitleModel(List<AiModelConfig> models) {
    final profileDefault = _profileGlobalDefaultTitleModel(models);
    if (profileDefault.configured) {
      return profileDefault.model;
    }
    return _legacyGlobalDefaultTitleModel(models);
  }

  static ({bool configured, AiModelConfig? model})
  _profileGlobalDefaultTitleModel(List<AiModelConfig> models) {
    for (final provider in models) {
      for (final modelId in provider.allModelIds) {
        if (!provider.profileFor(modelId).isGlobalDefaultTitleModel) {
          continue;
        }
        final candidate = provider.copyWith(
          modelId: modelId,
          availableModelIds: AiModelConfig.normalizeModelIds(<String>[
            ...provider.availableModelIds,
            modelId,
          ]),
        );
        return (
          configured: true,
          model: supportsTextTitleGeneration(candidate) ? candidate : null,
        );
      }
    }
    return (configured: false, model: null);
  }

  static AiModelConfig? _legacyGlobalDefaultTitleModel(
    List<AiModelConfig> models,
  ) {
    for (final provider in models) {
      if (!provider.isGlobalDefaultTitleModel) {
        continue;
      }
      final modelId =
          nullIfBlank(provider.defaultTitleModelId) ??
          nullIfBlank(provider.modelId);
      if (modelId == null) return null;
      final candidate = provider.copyWith(
        modelId: modelId,
        availableModelIds: AiModelConfig.normalizeModelIds(<String>[
          ...provider.availableModelIds,
          modelId,
        ]),
      );
      return supportsTextTitleGeneration(candidate) ? candidate : null;
    }
    return null;
  }

  static String _candidateKey(AiModelConfig model) {
    final providerId = nullIfBlank(model.id) ?? '';
    final modelId = nullIfBlank(model.modelId) ?? '';
    return '$providerId::$modelId';
  }

  static const Set<String> _nonTextModalityMarkers = <String>{
    'image',
    'audio',
    'video',
    'speech',
    'embedding',
  };
}
