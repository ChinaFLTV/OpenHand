import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_model_config.dart';

const int _minHttpStatusCode = 100;
const int _maxHttpStatusCode = 599;

String? resolveWebEngineApiKey(String? configured, String? fallback) {
  return configured != null && configured.isNotEmpty ? configured : fallback;
}

double? webEngineScoreFromValue(Object? value) {
  return optionalNonNegativeDoubleFromValue(value);
}

int webEngineNonNegativeIntFromValue(Object? value) {
  return nonNegativeIntFromValue(value, fallback: 0);
}

int? webEngineOptionalNonNegativeIntFromValue(Object? value) {
  return optionalNonNegativeIntFromValue(value);
}

int? webEngineHttpStatusFromValue(Object? value) {
  final parsed = optionalIntegralIntFromValue(value);
  if (parsed == null) return null;
  if (parsed < _minHttpStatusCode || parsed > _maxHttpStatusCode) {
    return null;
  }
  return parsed;
}

/// 解析复用 provider 的 API key：按 [configId] 命中 [availableModels]
/// 时返回其非空 token，未命中或未配置返回 null。WebSearch / WebFetch
/// 引擎上下文共用。
String? resolveWebEngineProviderApiKey(
  List<AiModelConfig> availableModels,
  String? configId,
) {
  if (configId == null || configId.isEmpty) return null;
  for (final m in availableModels) {
    if (m.id == configId) return m.token.isEmpty ? null : m.token;
  }
  return null;
}
