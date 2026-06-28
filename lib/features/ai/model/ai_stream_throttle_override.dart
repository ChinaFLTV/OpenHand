import '../../../shared/util/input_value_parsing.dart';

/// Per-thread-template override for stream output throttle settings.
///
/// 2026-05-17 — 流式输出节流的「每个线程模板独立覆盖」。当用户希望某
/// 个线程模板（比如 Hermes Talker）使用与全局不同的节流速率时，可以在
/// 设置面板里给该模板写一份覆盖；运行时按 templateId 查表，命中即用，
/// 未命中或字段为空时回退到全局值。
///
/// 持久化时只写非 null 字段，避免 noise 撑大 settings.json。
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

  /// 2026-05-19 — 会话级「启用节流」开关：
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
          ? this.charsPerSecond
          : charsPerSecond as int?,
      cardsPerSecond: identical(cardsPerSecond, _sentinel)
          ? this.cardsPerSecond
          : cardsPerSecond as int?,
      enabled: identical(enabled, _sentinel) ? this.enabled : enabled as bool?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (charsPerSecond != null) 'chars_per_second': charsPerSecond,
      if (cardsPerSecond != null) 'cards_per_second': cardsPerSecond,
      if (enabled != null) 'enabled': enabled,
    };
  }

  static AiStreamThrottleOverride? fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return null;
    final override = AiStreamThrottleOverride(
      charsPerSecond: optionalPositiveIntFromValue(json['chars_per_second']),
      cardsPerSecond: optionalPositiveIntFromValue(json['cards_per_second']),
      enabled: optionalBoolFromValue(json['enabled']),
    );
    return override.isEmpty ? null : override;
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
