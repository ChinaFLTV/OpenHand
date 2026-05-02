/// 2026-05-01 — 输入缓存运行时配置。
///
/// 由 [AiSessionController] 在每轮请求开始时根据 SettingsController 与
/// [AiSessionRuntimeContext] 装配，向下传递到 [AiChatClient.sendMessageStream]
/// 与 [AiProtocolAdapter.buildBody]，由具体协议适配器（当前只有
/// [ClaudeProtocolAdapter]）翻译为 `cache_control: {type: 'ephemeral'}` 标记。
///
/// `enabled=false` 时，所有适配器应表现为完全无行为变化（空操作）。
class AiInputCacheRuntimeConfig {
  const AiInputCacheRuntimeConfig({
    required this.enabled,
    required this.mode,
    required this.updateInterval,
    required this.breakpointCount,
    this.breakpointPositions = const <double>[],
  });

  /// 一个明确的"无缓存"哨兵；适配器收到 null 或 disabled 都走旧路径。
  static const AiInputCacheRuntimeConfig disabled = AiInputCacheRuntimeConfig(
    enabled: false,
    mode: 'allMessages',
    updateInterval: 10,
    breakpointCount: 4,
  );

  final bool enabled;

  /// 'allMessages' / 'userMessages' / 'tokens'.
  final String mode;
  final int updateInterval;

  /// Anthropic 上限就是 4，超过会报 400。
  final int breakpointCount;

  /// 2026-05-04 — 用户自定义的前 N-1 个静态缓存点位置（百分比 0..1，升序）。
  /// 长度 == [breakpointCount] - 1 时优先用此布点；否则适配器沿用 mode-based
  /// 自动布点。最后一个断点恒位于消息流末尾。
  final List<double> breakpointPositions;

  bool get isEffectivelyEnabled => enabled && breakpointCount > 0;
}
