import '../../../../shared/util/bounded_json_conversion.dart';
import '../../model/ai_model_config.dart';

/// 将 OpenRouter 的模型目录条目转换为 OpenHand 的模型档案。
/// 单条数据异常时返回 null，由同步服务跳过该条并继续处理。
AiModelProfile? mapOpenRouterModel(Object? raw) {
  if (raw is! Map) return null;
  final model = _stringKeyedMap(raw);
  final id = _string(model['id']);
  if (id == null) return null;

  final architecture = _stringKeyedMap(model['architecture']);
  final inputModalities = _stringList(architecture['input_modalities']);
  final outputModalities = _stringList(architecture['output_modalities']);
  final modalityValues = <String>{...inputModalities, ...outputModalities};
  final supportedModalities = modalityValues
      .map(AiModelModality.fromStorage)
      .whereType<AiModelModality>()
      .toSet();
  final capabilities = <AiModelCapability>{
    for (final value in outputModalities)
      if (value != 'text' && value != 'file') ..._capabilityForModality(value),
  };
  final loweredId = id.toLowerCase();
  if (loweredId.contains('embed')) {
    capabilities.add(AiModelCapability.embeddingGeneration);
  }
  if (loweredId.contains('rerank') || loweredId.contains('re-rank')) {
    capabilities.add(AiModelCapability.rerank);
  }

  final topProvider = _stringKeyedMap(model['top_provider']);
  final pricing = _stringKeyedMap(model['pricing']);
  final reasoning = _stringKeyedMap(model['reasoning']);
  final links = _stringKeyedMap(model['links']);
  final supportedParameters = _stringList(model['supported_parameters']);
  final supportedEfforts = _stringList(reasoning['supported_efforts']);
  final hasReasoning =
      reasoning.isNotEmpty ||
      supportedParameters.contains('reasoning') ||
      supportedParameters.contains('include_reasoning');
  final effortOptions = AiReasoningEffortOption.standardValues(
    supportedEfforts,
  );
  final maxOutputLength = _positiveInt(topProvider['max_completion_tokens']);
  final defaultEffort = _string(reasoning['default_effort']);

  return AiModelProfile(
    displayName: _displayName(model, id),
    description: _string(model['description']),
    isMultimodal: modalityValues.isEmpty
        ? null
        : modalityValues.any((value) => value != 'text'),
    supportedModalities: supportedModalities,
    supportsAttachments: inputModalities.isEmpty
        ? null
        : inputModalities.any((value) => value != 'text'),
    maxContextLength: _positiveInt(model['context_length']),
    maxOutputLength: maxOutputLength,
    maxThinkingLength: hasReasoning ? maxOutputLength : null,
    thinkingEnabled:
        reasoning['mandatory'] == true || reasoning['default_enabled'] == true
        ? true
        : null,
    reasoningEffortControlEnabled:
        supportedEfforts.isNotEmpty || supportedParameters.contains('reasoning')
        ? true
        : null,
    reasoningEffort:
        defaultEffort ??
        (effortOptions.isEmpty ? null : effortOptions.first.value),
    reasoningEffortOptions: effortOptions,
    capabilities: capabilities,
    inputUsdPer1M: _price(pricing['prompt']),
    outputUsdPer1M: _price(pricing['completion']),
    cacheReadUsdPer1M: _price(pricing['input_cache_read']),
    cacheWriteUsdPer1M: _price(pricing['input_cache_write']),
    canonicalSlug: _string(model['canonical_slug']),
    huggingFaceId: _string(model['hugging_face_id']),
    created: _integer(model['created']),
    architecture: architecture.isEmpty
        ? null
        : AiModelArchitectureMetadata(
            modality: _string(architecture['modality']),
            inputModalities: inputModalities,
            outputModalities: outputModalities,
            tokenizer: _string(architecture['tokenizer']),
            instructType: _string(architecture['instruct_type']),
          ),
    supportedParameters: supportedParameters,
    defaultParameters: _jsonMap(model['default_parameters']),
    supportedVoices: _stringList(model['supported_voices']),
    knowledgeCutoff: _string(model['knowledge_cutoff']),
    expirationDate: _string(model['expiration_date']),
    links: links.isEmpty
        ? null
        : AiModelLinksMetadata(details: _string(links['details'])),
  );
}

Set<AiModelCapability> _capabilityForModality(String value) {
  return switch (value) {
    'image' => <AiModelCapability>{AiModelCapability.imageGeneration},
    'video' => <AiModelCapability>{AiModelCapability.videoGeneration},
    'audio' => <AiModelCapability>{AiModelCapability.audioGeneration},
    _ => const <AiModelCapability>{},
  };
}

String? _displayName(Map<String, Object?> model, String id) {
  final name = _string(model['name']) ?? id;
  final separator = name.indexOf(': ');
  return separator < 0 ? name : name.substring(separator + 2);
}

Map<String, Object?> _stringKeyedMap(Object? value) {
  if (value is! Map) return <String, Object?>{};
  return <String, Object?>{
    for (final entry in value.entries) '${entry.key}': entry.value,
  };
}

Map<String, Object?> _jsonMap(Object? value) {
  final map = _stringKeyedMap(value);
  return convertToJsonSafeMap(map);
}

List<String> _stringList(Object? value) {
  if (value is! List) return <String>[];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String? _string(Object? value) {
  if (value is! String) return null;
  final result = value.trim();
  return result.isEmpty ? null : result;
}

int? _positiveInt(Object? value) {
  final parsed = _integer(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

int? _integer(Object? value) {
  if (value is num) return value.isFinite ? value.toInt() : null;
  return int.tryParse('$value');
}

double? _price(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null || !parsed.isFinite || parsed < 0) return null;
  return parsed * 1000000;
}
