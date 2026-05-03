# MCP 工具懒加载（Lazy Loading）

> 模仿 Claude Code 的 Tool Search 模式：当 MCP 工具集庞大时，按需通过
> `ToolSearch` 工具拉取相关 schema，避免每轮都把全量 MCP 工具说明塞进 prompt。

## 1. 何时启用

`Settings → MCP → 懒加载` 提供三档模式：

| 模式       | 行为                                                                                    |
| ---------- | --------------------------------------------------------------------------------------- |
| `disabled` | 不启用懒加载。`ToolSearch` 工具不出现在 catalog 中。所有 MCP 工具的完整 schema 全量注入 prompt。 |
| `auto`（默认） | 估算本轮 MCP 工具集合的 token 体积，超过 `MCP 工具压缩阈值`（默认 80 000 tokens）才转入懒加载。 |
| `enabled`  | 始终懒加载：除已通过 `ToolSearch` 拉取的工具外，其余仅以名字列表呈现，schema 延后按需加载。 |

阈值（`MCP 工具压缩阈值`）的可调范围 **1 000 ~ 1 000 000** tokens，按照 ~4 chars/token 估算。

> 切换为 `disabled` 后，`ToolSearch` 工具会从 catalog 与 prompt 注入双侧同时移除。

## 2. 模型如何按需加载工具

懒加载激活后，prompt 的 `# [2] Tool Catalog` 末尾会出现：

```
## MCP Tools (lazy-loaded — descriptions deferred)
- mcp__svr__tool_a
- mcp__svr__tool_b
- ...

Use the `ToolSearch` tool to load any tool's full JSONSchema before invoking it.
```

模型可通过两种方式调用 `ToolSearch`：

1. **关键词查询** — `query: "k8s pod logs"`，按照 part-match 10 / substring 6 / full 3
   / description word-boundary 2 的评分排序，取前 `max_results`（默认 20，最大 50）。
2. **精确选取** — `query: "select:mcp__svr__tool_a, select:mcp__svr__tool_b"` 直接命中。

`ToolSearch` 返回一个 `<functions>` 块，其中包含每个匹配工具的完整 JSONSchema。
**调用后该轮以及后续轮次**模型可直接以工具名调用，无需再次走 `ToolSearch`。

## 3. UI 反馈

- **会话顶栏 Pill**：`MCP 已载 N/M`，悬停查看 deferred 总数与模式。
- **工具调用卡 Banner**：`✅ ToolSearch loaded N of M deferred MCP tool(s).`（成功）
  或 `⚠ ToolSearch matched 0 of M deferred MCP tool(s).`（无命中）。
- **SnackBar 通知**：每次 `ToolSearch` 成功加载会弹出 floating SnackBar
  「ToolSearch 已加载 N/M 个 MCP 工具」，附「查看列表」action。
- **「查看列表」对话框**：列出本会话所有已通过 `ToolSearch` 加载的工具完整名，每行可一键
  **复制 `select:NAME`** 供模型在下一轮明确复用，标题栏的「**清空已加载列表**」按钮会重置
  累计名单（下一轮被点中的工具会重新走懒加载路径）。
- **设置页快捷入口**：`Settings → MCP → 「查看本会话已加载列表」` 直接打开同款对话框。

## 4. Hardness 引擎的支持

`HardnessApiPhaseRunner` 通过共享的 `McpLazyLoadingApplier.apply` 同样套用懒加载策略，
以 `phaseSessionId` 为粒度累积加载名单。`OpenHandHomePage._wireHardnessApiMode` 注入
`onToolSearchLoaded` 回调，在 phase 内同样弹出带「查看列表」action 的 SnackBar。

## 5. 实现要点

| 文件                                                                                          | 角色                                                  |
| --------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| [`lib/features/ai/tools/ai_tool_search_tool.dart`](../lib/features/ai/tools/ai_tool_search_tool.dart) | 注册 `ToolSearch` 工具，承载评分 / select 解析 / `<functions>` 渲染 |
| [`lib/features/mcp/service/mcp_lazy_loading_applier.dart`](../lib/features/mcp/service/mcp_lazy_loading_applier.dart) | 三档模式套用、catalog 裁剪、ToolSearch 描述附 deferred 名单     |
| [`lib/features/ai/service/mcp_loaded_tools_tracker.dart`](../lib/features/ai/service/mcp_loaded_tools_tracker.dart) | 累计 `sessionId → loadedNames` + 广播加载事件         |
| [`lib/features/mcp/widgets/tool_search_loaded_dialog.dart`](../lib/features/mcp/widgets/tool_search_loaded_dialog.dart) | 复用的列表对话框（复制 `select:` / 清空入口）           |
| [`lib/features/mcp/model/mcp_lazy_loading_mode.dart`](../lib/features/mcp/model/mcp_lazy_loading_mode.dart) | 三态枚举（`disabled` / `auto` / `enabled`）           |

## 6. 测试

- [`test/features/ai/service/mcp_loaded_tools_tracker_test.dart`](../test/features/ai/service/mcp_loaded_tools_tracker_test.dart)：
  7 case 覆盖 absorber / 排序 / revision 递增 / clear / 多会话隔离。
- [`test/features/mcp/tool_search_loaded_dialog_test.dart`](../test/features/mcp/tool_search_loaded_dialog_test.dart)：
  6 case 覆盖渲染 / 空占位 / `onClear=null` 隐藏按钮 / 复制至剪贴板 / 清空交互 / 关闭。

## 7. 参考

- Claude Code Tool Search 模式（`tst` / `tst-auto` / `standard`）：评分公式来源参考
  Anthropic Claude Code 1.x 源码。
