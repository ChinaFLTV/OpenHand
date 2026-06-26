# Message Gateway feature

## 职责
Web 端控制面板与桌面 App 之间的消息网关：管理 web 平台配置、模型选项、用户指令白名单、命令审批、文件写入审批等。

## 形态
Controller-bearing。作为跨 feature 协调器，构造时强依赖 ai/crons/instructions/mcp/memory/skills 等 controller。

## 对外 API
- `MessageGatewayController` — Provider 提供，含 platform/模型/审批等状态
- `WebMessagePlatformConfig` — 领域模型
- `WebWriteApprovalRequest` — service 内部 DTO（barrel 经 `show` 暴露）
- `MessageGatewayModule.bootstrap(...)` / `MessageGatewayModule.providers(m)`
- `MessageGatewayView` — 设置页内的消息网关编辑 widget
- barrel: `features/message_gateway/index.dart`

## 装配特点
- 与 hooks/instructions/memory/skills/crons/mcp 不同：bootstrap **不能** 早 kick-off。它必须在依赖的所有 controller resolve 之后再调用。
- `pluginServiceController` 通过 controller 的 public field 后绑（plugin_service 在 messages 之后才 await）。

## 依赖
- `data/message_gateway_store.dart` / `service/web_message_platform_service.dart`（feature 内私有）
- 跨 feature 依赖通过对应 feature barrel 注入；`scripts/check_imports.dart` 会在 Web 构建脚本中强制检查。

## 不变量
- 构造同步完成；首次 `initialize()` 触发持久化加载与 web socket 连接
- pluginServiceController 必须在 messages bootstrap 后绑定
