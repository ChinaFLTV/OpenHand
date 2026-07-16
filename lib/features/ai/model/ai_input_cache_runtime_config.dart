/// 输入缓存运行时配置。
///
/// 由 [AiSessionController] 在每轮请求开始时根据 SettingsController 与
/// [AiSessionRuntimeContext] 装配，向下传递到 [AiChatClient.sendMessageStream]
/// 与 [AiProtocolAdapter.buildBody]。协议适配器可将其翻译为 Claude native
/// `cache_control`、GPT-5.6+ `prompt_cache_breakpoint`，或兼容服务商的
/// 会话亲和键。
///
/// `enabled=false` 时，所有适配器应表现为完全无行为变化（空操作）。
class AiInputCacheRuntimeConfig {
  const AiInputCacheRuntimeConfig({
    required this.enabled,
    required this.mode,
    required this.updateInterval,
    required this.breakpointCount,
    this.breakpointPositions = const <double>[],
    this.cacheAffinityId = '',
    this.promptCacheKey = '',
    this.stablePrefixMessageCount = 0,
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

  /// Anthropic 与 GPT-5.6+ 每次请求最多写入 4 个显式缓存断点。
  final int breakpointCount;

  /// 用户自定义的前 N-1 个静态缓存点位置（百分比 0..1，升序）。
  /// 长度 == [breakpointCount] - 1 时优先用此布点；否则适配器沿用 mode-based
  /// 自动布点。最后一个断点恒位于消息流末尾。
  final List<double> breakpointPositions;

  /// 稳定会话亲和键。OpenAI-compatible provider 可用它把同一会话路由到
  /// 同一缓存后端，例如 xAI 的 `x-grok-conv-id` 或 OpenRouter 的
  /// `session_id` / `x-session-id`。
  final String cacheAffinityId;

  /// 稳定 Prompt 前缀缓存键。仅用于 `prompt_cache_key` 这类显式缓存键字段；
  /// 不用于带会话语义的 header / `session_id`，避免跨线程共享会话状态。
  final String promptCacheKey;

  /// Prompt Builder 生成的稳定前缀消息数。GPT-5.6+ Responses 协议据此在
  /// 静态核心与运行时工具目录之间放置统一断点；其他协议忽略该值。
  final int stablePrefixMessageCount;

  bool get isEffectivelyEnabled => enabled && breakpointCount > 0;
}
