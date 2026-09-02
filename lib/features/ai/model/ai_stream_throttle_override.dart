import '../../../shared/util/input_value_parsing.dart';
import 'ai_stream_throttle_policy.dart';

/// 流式输出节流的「每个线程模板独立覆盖」。当用户希望某
/// 个线程模板（比如 Hermes Talker）使用与全局不同的节流速率时，可以在
/// 设置面板里给该模板写一份覆盖；运行时按 templateId 查表，命中即用，
/// 未命中或字段为空时回退到全局值。
///
/// 持久化时只写非 null 字段，避免无效数据撑大设置记录。
class AiStreamThrottleOverride {
  const AiStreamThrottleOverride({
    this.charsPerSecond,
    this.cardsPerSecond,
    this.enabled,
  });

  /// 每秒最多向当前流式卡片追加多少字符；null = 沿用全局。
  final int? charsPerSecond;

  /// 每秒最多向当前会话追加多少新卡片；null = 沿用全局。
  final int? cardsPerSecond;

  /// 会话级「启用节流」开关：
  ///   * null  → 沿用全局 `aiStreamThrottleEnabled`；
  ///   * false → 强制关闭节流（即便全局已开启），全速 pass-through；
  ///   * true  → 强制开启节流（即便全局已关闭），按 chars/cards 限速。
  /// 与 chars/cards 字段正交：用户可以仅切换开关而不改速率。
  final bool? enabled;

  bool get isEmpty =>
      charsPerSecond == null && cardsPerSecond == null && enabled == null;

  AiStreamThrottleOverride copyWith({
    Object? charsPerSecond = _sentinel,
    Object? cardsPerSecond = _sentinel,
    Object? enabled = _sentinel,
  }) {
    return AiStreamThrottleOverride(
      charsPerSecond: identical(charsPerSecond, _sentinel)
          ? normalizeCharsPerSecond(this.charsPerSecond)
          : _nullableIntPatch(charsPerSecond, _charsPerSecondRange),
      cardsPerSecond: identical(cardsPerSecond, _sentinel)
          ? normalizeCardsPerSecond(this.cardsPerSecond)
          : _nullableIntPatch(cardsPerSecond, _cardsPerSecondRange),
      enabled: identical(enabled, _sentinel) ? this.enabled : enabled as bool?,
    );
  }

  Map<String, Object?> toJson() {
    final normalizedCharsPerSecond = normalizeCharsPerSecond(charsPerSecond);
    final normalizedCardsPerSecond = normalizeCardsPerSecond(cardsPerSecond);
    return <String, Object?>{
      if (normalizedCharsPerSecond != null)
        'chars_per_second': normalizedCharsPerSecond,
      if (normalizedCardsPerSecond != null)
        'cards_per_second': normalizedCardsPerSecond,
      if (enabled != null) 'enabled': enabled,
    };
  }

  static AiStreamThrottleOverride? fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return null;
    final override = AiStreamThrottleOverride(
      charsPerSecond: charsPerSecondFromValue(json['chars_per_second']),
      cardsPerSecond: cardsPerSecondFromValue(json['cards_per_second']),
      enabled: optionalBoolFromValue(json['enabled']),
    );
    return override.isEmpty ? null : override;
  }

  static const int minCharsPerSecond =
      AiStreamThrottlePolicy.minMaxCharsPerSecond;
  static const int maxCharsPerSecond =
      AiStreamThrottlePolicy.maxMaxCharsPerSecond;
  static const int minCardsPerSecond =
      AiStreamThrottlePolicy.minMaxMessageCardsPerSecond;
  static const int maxCardsPerSecond =
      AiStreamThrottlePolicy.maxMaxMessageCardsPerSecond;

  static const IntValueRange _charsPerSecondRange = IntValueRange(
    fallback: minCharsPerSecond,
    min: minCharsPerSecond,
    max: maxCharsPerSecond,
  );
  static const IntValueRange _cardsPerSecondRange = IntValueRange(
    fallback: minCardsPerSecond,
    min: minCardsPerSecond,
    max: maxCardsPerSecond,
  );

  static int? charsPerSecondFromValue(Object? value) {
    return _nonNegativeIntegralIntInRange(value, _charsPerSecondRange);
  }

  static int? normalizeCharsPerSecond(int? value) {
    return _nonNegativeIntInRange(value, _charsPerSecondRange);
  }

  static int? cardsPerSecondFromValue(Object? value) {
    return _nonNegativeIntegralIntInRange(value, _cardsPerSecondRange);
  }

  static int? normalizeCardsPerSecond(int? value) {
    return _nonNegativeIntInRange(value, _cardsPerSecondRange);
  }

  @override
  bool operator ==(Object other) {
    return other is AiStreamThrottleOverride &&
        other.charsPerSecond == charsPerSecond &&
        other.cardsPerSecond == cardsPerSecond &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(charsPerSecond, cardsPerSecond, enabled);
}

const Object _sentinel = Object();

int? _nullableIntPatch(Object? value, IntValueRange range) {
  if (value == null) return null;
  if (value is! int) return null;
  return _nonNegativeIntInRange(value, range);
}

int? _nonNegativeIntegralIntInRange(Object? value, IntValueRange range) {
  final parsed = optionalNonNegativeIntegralIntFromValue(value);
  return _nonNegativeIntInRange(parsed, range);
}

int? _nonNegativeIntInRange(int? value, IntValueRange range) {
  return value == null || value < 0 ? null : range.normalize(value);
}
