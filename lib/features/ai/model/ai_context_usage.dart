import '../../../shared/util/input_value_parsing.dart';

const String aiContextUsageMetadataKey = 'context_usage_breakdown';
const String aiContextUsedTokensMetadataKey =
    'context_budget_estimated_prompt_tokens';
const String aiContextWindowTokensMetadataKey =
    'context_budget_effective_window_tokens';
const double aiManualCompactionMinContextUsageRatio = 0.20;

class AiContextWindowUsage {
  const AiContextWindowUsage({
    required this.usedTokens,
    required this.windowTokens,
  });

  factory AiContextWindowUsage.fromMetadata(Map<String, Object?> metadata) {
    return AiContextWindowUsage(
      usedTokens:
          optionalNonNegativeIntegralIntFromValue(
            metadata[aiContextUsedTokensMetadataKey],
          ) ??
          0,
      windowTokens:
          optionalNonNegativeIntegralIntFromValue(
            metadata[aiContextWindowTokensMetadataKey],
          ) ??
          0,
    );
  }

  final int usedTokens;
  final int windowTokens;

  bool get hasData => usedTokens > 0 && windowTokens > 0;

  double get ratio {
    if (!hasData) return 0;
    return (usedTokens / windowTokens).clamp(0.0, 1.0);
  }

  int get percent => (ratio * 100).round();

  bool get canManuallyCompact =>
      hasData && ratio > aiManualCompactionMinContextUsageRatio;
}

enum AiContextUsageCategory {
  systemPrompt('system_prompt'),
  builtinTools('builtin_tools'),
  mcp('mcp'),
  instructions('instructions'),
  memory('memory'),
  skills('skills'),
  hooks('hooks'),
  conversation('conversation'),
  runtime('runtime');

  const AiContextUsageCategory(this.storageValue);

  final String storageValue;

  static AiContextUsageCategory? fromStorage(Object? value) {
    return enumByStorageValue(values, value, (item) => item.storageValue);
  }
}

enum AiContextTokenSource {
  estimated('estimated'),
  provider('provider');

  const AiContextTokenSource(this.storageValue);

  final String storageValue;

  static AiContextTokenSource fromStorage(Object? value) {
    return enumByStorageValueOr(
      values,
      value,
      (item) => item.storageValue,
      fallback: AiContextTokenSource.estimated,
    );
  }
}

class AiContextUsageItem {
  const AiContextUsageItem({
    required this.category,
    required this.characterCount,
    required this.tokenCount,
  });

  final AiContextUsageCategory category;
  final int characterCount;
  final int tokenCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'category': category.storageValue,
    'character_count': characterCount,
    'token_count': tokenCount,
  };
}

class AiContextUsageBreakdown {
  const AiContextUsageBreakdown({
    required this.items,
    required this.totalCharacters,
    required this.totalTokens,
    required this.tokenSource,
  });

  factory AiContextUsageBreakdown.fromCharacterCounts(
    Map<AiContextUsageCategory, int> characterCounts, {
    required int totalTokens,
    AiContextTokenSource tokenSource = AiContextTokenSource.estimated,
  }) {
    final normalized = <AiContextUsageCategory, int>{
      for (final category in AiContextUsageCategory.values)
        category: characterCounts[category]?.clamp(0, 1 << 62) ?? 0,
    };
    final totalCharacters = normalized.values.fold<int>(0, (a, b) => a + b);
    final safeTotalTokens = totalTokens.clamp(0, 1 << 62);
    final tokenCounts = _distributeTokens(
      normalized,
      totalCharacters: totalCharacters,
      totalTokens: safeTotalTokens,
    );
    return AiContextUsageBreakdown(
      items: List<AiContextUsageItem>.unmodifiable(
        AiContextUsageCategory.values.map(
          (category) => AiContextUsageItem(
            category: category,
            characterCount: normalized[category] ?? 0,
            tokenCount: tokenCounts[category] ?? 0,
          ),
        ),
      ),
      totalCharacters: totalCharacters,
      totalTokens: safeTotalTokens,
      tokenSource: tokenSource,
    );
  }

  final List<AiContextUsageItem> items;
  final int totalCharacters;
  final int totalTokens;
  final AiContextTokenSource tokenSource;

  bool get hasData => totalCharacters > 0 && totalTokens > 0;

  static AiContextUsageBreakdown? fromMetadata(Map<String, Object?> metadata) {
    final raw = metadata[aiContextUsageMetadataKey];
    if (raw is! Map) return null;
    final json = stringKeyedMapFromValue(raw);
    final rawItems = json['items'];
    if (rawItems is! List) return null;
    final characterCounts = <AiContextUsageCategory, int>{};
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = stringKeyedMapFromValue(rawItem);
      final category = AiContextUsageCategory.fromStorage(item['category']);
      if (category == null) continue;
      characterCounts[category] =
          optionalNonNegativeIntegralIntFromValue(item['character_count']) ?? 0;
    }
    final totalTokens =
        optionalNonNegativeIntegralIntFromValue(json['total_tokens']) ?? 0;
    final parsed = AiContextUsageBreakdown.fromCharacterCounts(
      characterCounts,
      totalTokens: totalTokens,
      tokenSource: AiContextTokenSource.fromStorage(json['token_source']),
    );
    return parsed.hasData ? parsed : null;
  }

  AiContextUsageBreakdown withProviderTokenTotal(int total) {
    return AiContextUsageBreakdown.fromCharacterCounts(
      <AiContextUsageCategory, int>{
        for (final item in items) item.category: item.characterCount,
      },
      totalTokens: total,
      tokenSource: AiContextTokenSource.provider,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'token_source': tokenSource.storageValue,
    'total_characters': totalCharacters,
    'total_tokens': totalTokens,
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };

  static Map<AiContextUsageCategory, int> _distributeTokens(
    Map<AiContextUsageCategory, int> characterCounts, {
    required int totalCharacters,
    required int totalTokens,
  }) {
    final result = <AiContextUsageCategory, int>{
      for (final category in AiContextUsageCategory.values) category: 0,
    };
    if (totalTokens <= 0) return result;
    if (totalCharacters <= 0) {
      result[AiContextUsageCategory.runtime] = totalTokens;
      return result;
    }
    final remainders = <({AiContextUsageCategory category, int value})>[];
    var allocated = 0;
    for (final category in AiContextUsageCategory.values) {
      final characters = characterCounts[category] ?? 0;
      final weighted = totalTokens * characters;
      final tokens = weighted ~/ totalCharacters;
      result[category] = tokens;
      allocated += tokens;
      remainders.add((category: category, value: weighted % totalCharacters));
    }
    remainders.sort((a, b) {
      final byRemainder = b.value.compareTo(a.value);
      return byRemainder != 0
          ? byRemainder
          : a.category.index.compareTo(b.category.index);
    });
    final remaining = totalTokens - allocated;
    for (var index = 0; index < remaining; index += 1) {
      final category = remainders[index % remainders.length].category;
      result[category] = (result[category] ?? 0) + 1;
    }
    return result;
  }
}
