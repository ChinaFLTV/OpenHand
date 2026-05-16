# Mcp feature

## 职责
管理 MCP（Model Context Protocol）服务器列表：连接、健康检查、工具发现、关键词倒排索引、stdio process 管理、工具搜索历史。

## 对外 API
- `McpController` — Provider 提供，含 servers / tools / isLoading 与 connect/disconnect/refresh 等
- 领域模型：`McpServer / McpTool / McpServerHealth / McpKeywordIndexUpdateMode / McpLazyLoadingMode / McpStdioMirrorMode`
- service：`McpToolDiscoveryService / McpLazyLoadingApplier / ToolSearchHistoryExportPrefs / ToolSearchReplayDispatcher`
- `McpModule.bootstrap(initialFilePath:)` / `McpModule.providers(m)`
- `McpView` / `ToolSearchLoadedDialog` — 设置页 widget
- barrel: `features/mcp/index.dart`

## 依赖
- `data/mcp_store.dart`（JSON 文件持久化，路径由 main.dart 通过 OpenHandPaths 注入）
- 跨 feature：widgets/service 内仍残留对 features/ai/* 的若干 deep import，P1 ai 拆解后清

## 不变量
- 同一 server id 在 servers 内唯一
- isOperating 期间禁止并发触发新操作
- 构造同步完成，首次 refresh 触发服务器列表读取
