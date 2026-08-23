import '../../../shared/util/input_value_parsing.dart';

class AiOneMillionContextPolicy {
  const AiOneMillionContextPolicy._();

  static const int contextTokens = 1000000;
  static const String contextTokensText = '1000000';
  static const String modelIdSuffix = '[1M]';
  static final RegExp _modelIdSuffixRunPattern = RegExp(
    r'(?:\s*\[1m\])+$',
    caseSensitive: false,
  );

  static bool isEnabledBy({
    required String modelId,
    required String maxContextLength,
    bool includeContextLength = true,
  }) {
    return hasModelIdSuffix(modelId) ||
        includeContextLength && isPolicyContextLengthText(maxContextLength);
  }

  static bool isPolicyContextLengthText(String value) {
    return optionalPositiveIntFromText(value) == contextTokens;
  }

  static bool hasModelIdSuffix(String modelId) {
    return _modelIdSuffixRunPattern.hasMatch(modelId.trim());
  }

  static String normalizeModelId(String modelId) {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final base = stripModelIdSuffix(trimmed);
    return '${base.isEmpty ? 'model' : base}$modelIdSuffix';
  }

  static String restoreModelId({
    required String currentModelId,
    String? snapshotModelId,
  }) {
    final snapshot = snapshotModelId?.trim();
    final current = currentModelId.trim();
    if (snapshot != null &&
        snapshot.isNotEmpty &&
        current == normalizeModelId(snapshot)) {
      return snapshot;
    }
    if (hasModelIdSuffix(current)) {
      final stripped = stripModelIdSuffix(current);
      return stripped.isEmpty ? 'model' : stripped;
    }
    return current;
  }

  static String restoreContextLength({
    required String currentMaxContextLength,
    required String fallbackMaxContextLength,
    String? snapshotMaxContextLength,
  }) {
    if (!isPolicyContextLengthText(currentMaxContextLength)) {
      return currentMaxContextLength.trim();
    }
    if (snapshotMaxContextLength != null) {
      return snapshotMaxContextLength.trim();
    }
    return fallbackMaxContextLength.trim();
  }

  static String copyModelId(String sourceModelId, int index) {
    final trimmed = sourceModelId.trim();
    final base = trimmed.isEmpty ? 'model' : trimmed;
    if (!hasModelIdSuffix(base)) {
      return '$base-Copy-$index';
    }
    final withoutSuffix = stripModelIdSuffix(base);
    return '${withoutSuffix.isEmpty ? 'model' : withoutSuffix}-Copy-$index$modelIdSuffix';
  }

  static String stripModelIdSuffix(String modelId) {
    return modelId
        .trim()
        .replaceFirst(_modelIdSuffixRunPattern, '')
        .trimRight();
  }
}
