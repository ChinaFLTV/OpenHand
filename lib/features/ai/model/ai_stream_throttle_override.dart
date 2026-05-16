/// Per-thread-template override for stream output throttle settings.
///
/// 2026-05-17 — 流式输出节流的「每个线程模板独立覆盖」。当用户希望某
/// 个线程模板（比如 Hermes Talker）使用与全局不同的节流速率时，可以在
/// 设置面板里给该模板写一份覆盖；运行时按 templateId 查表，命中即用，
/// 未命中或字段为空时回退到全局值。
///
/// 持久化时只写非 null 字段，避免 noise 撑大 settings.json。
class AiStreamThrottleOverride {
  const AiStreamThrottleOverride({this.charsPerSecond, this.cardsPerSecond});

  /// 每秒最多向当前流式卡片追加多少字符；null = 沿用全局。
  final int? charsPerSecond;

  /// 每秒最多向当前会话追加多少新卡片；null = 沿用全局。
  final int? cardsPerSecond;

  bool get isEmpty => charsPerSecond == null && cardsPerSecond == null;

  AiStreamThrottleOverride copyWith({
    Object? charsPerSecond = _sentinel,
    Object? cardsPerSecond = _sentinel,
  }) {
    return AiStreamThrottleOverride(
      charsPerSecond: identical(charsPerSecond, _sentinel)
          ? this.charsPerSecond
          : charsPerSecond as int?,
      cardsPerSecond: identical(cardsPerSecond, _sentinel)
          ? this.cardsPerSecond
          : cardsPerSecond as int?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (charsPerSecond != null) 'chars_per_second': charsPerSecond,
      if (cardsPerSecond != null) 'cards_per_second': cardsPerSecond,
    };
  }

  static AiStreamThrottleOverride? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final c = raw['chars_per_second'];
    final m = raw['cards_per_second'];
    final override = AiStreamThrottleOverride(
      charsPerSecond: c is int ? c : null,
      cardsPerSecond: m is int ? m : null,
    );
    return override.isEmpty ? null : override;
  }

  @override
  bool operator ==(Object other) {
    return other is AiStreamThrottleOverride &&
        other.charsPerSecond == charsPerSecond &&
        other.cardsPerSecond == cardsPerSecond;
  }

  @override
  int get hashCode => Object.hash(charsPerSecond, cardsPerSecond);
}

const Object _sentinel = Object();
