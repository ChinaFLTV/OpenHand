/// MCP 工具懒加载模式。控制是否在系统提示词中预加载所有 MCP 工具
/// 的完整 schema，还是改用 `ToolSearch` 内建工具按需检索。
///
/// 灵感来自 Claude Code 的 ENABLE_TOOL_SEARCH (auto / true / false)：
///   - [disabled]: 始终把全部 MCP 工具 schema 预先注入；ToolSearch 不可见。
///   - [auto]:     当所有 MCP 工具描述合计超过 `mcpLazyLoadingThresholdTokens`
///                  时才启用懒加载；否则等同 disabled。默认。
///   - [enabled]:  始终启用懒加载——MCP 工具默认从目录中剥离，模型必须先
///                  调用 ToolSearch 才能拿到对应 schema。
enum McpLazyLoadingMode {
  disabled('disabled'),
  auto('auto'),
  enabled('enabled');

  const McpLazyLoadingMode(this.storageValue);

  final String storageValue;

  static McpLazyLoadingMode fromStorage(String? raw) {
    final v = raw?.trim().toLowerCase();
    for (final mode in McpLazyLoadingMode.values) {
      if (mode.storageValue == v) return mode;
    }
    return McpLazyLoadingMode.auto;
  }
}
