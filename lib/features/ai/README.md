# Ai feature

OpenHand 桌面端 AI 会话核心，状态机心脏，由 `AiSessionController` 统一管理会话生命周期。

## 形态
Controller-bearing。`AiModule.bootstrap()` 注入 hooks executor / skills dir provider / memory controller provider，返回 controller 实例。main.dart 早 kick-off，await 后挂入 MultiProvider。

## 对外 API（barrel）
入口：`features/ai/index.dart`。

- **Module**：`AiModule.bootstrap()` / `AiModule.providers(m)`
- **Controller**：`AiSessionController`（状态机心脏）
- **Model**：会话、模型配置、上下文、用量与内置工具等领域模型
- **Service**：按聊天、Prompt、运行时、文件、媒体、沙箱与 Web 能力分组
- **Tool**：按文件、终端、搜索、Web、Git、规划和资源能力分组
- **Store**：`AiSessionStore`（data/）

## 目录组织

```
lib/features/ai/
  ai_module.dart                  # 装配入口
  ai_session_controller.dart      # 状态机心脏
  _ai_session_models.dart         # part of controller
  _ai_session_utils.dart          # part of controller
  index.dart                      # barrel
  README.md
  data/
    ai_session_store.dart         # SQLite 持久化
  model/                          # 领域模型
  service/                        # 按能力分组的服务
    chat/                         # ai_chat_service, ai_protocol_adapter, ai_transport_diagnostic_messages
    prompt/                       # ai_prompt_builder, ai_prompt_template_repository, ai_prompt_template_assembly
    runtime/                      # ai_tool_execution_registry, ai_tool_runtime_service, ai_plan_approval_detector
    dsml/                         # ai_dsml_partial_stream_scanner, ai_dsml_tool_call_parser
    fs/                           # ai_file_history_service, ai_file_mutation_ledger, ai_file_tracker_service, ai_attachment_service
    bash/                         # ai_bash_tool_service
    sandbox/                      # ai_sandbox_service, ai_sandbox_proxy_service
    git/                          # ai_git_snapshot_service
    lsp/                          # ai_lsp_managed_install_service, lsp_client_service
    media/                        # ai_image_generation_service, ai_image_summary_extractor, media_cache_service
    self_learning/                # self_learning_dispatcher / runner / scheduler
    hook/                         # ai_claude_hook_service
    session_io/                   # ai_session_jsonl_exporter, ai_token_usage_parser
    workspace/                    # ai_workspace_instruction_service
    model_registry/               # ai_model_scanner
    mcp_bridge/                   # mcp_loaded_tools_tracker
    operations/                   # 模型操作与媒体能力
    usage/                        # 用量跟踪
    web_engine/                   # web_engine_base / cache_store_base / concurrency / http_exception / json_utils / quality / telemetry_store_base
    web_fetch/                    # web_fetch_orchestrator / engine / direct_engines / scrape_engines / search_engines / cache_store / telemetry_store
    web_search/                   # web_search_orchestrator / engine / api_engines / html_engines / provider_engines / cache_store / telemetry_store
  tools/                          # 按能力分组的内置工具
    agents/                       # 智能体工具
    fs/                           # read/write/edit/multi_edit/delete/glob/ls/file_read_renderer/apply_file_diffs/notebook_edit (10)
    bash/                         # bash/bash_background
    search/                       # grep/codebase_search/tool_search
    web/                          # web_fetch/web_search
    lsp/                          # lsp/read_lints
    git/                          # git
    planning/                     # exit_plan_mode/todo_write/task/ask_user_choice
    memory/                       # memory
    knowledge/                    # knowledge_base
    skill/                        # skill_manager
    terminal/                     # MachineTerminal
    ai_tool.dart                  # 基类（不分类）
    ai_tool_registry.dart         # 工具注册中心（不分类）
    ai_tool_execution_context.dart # 执行上下文（不分类）
    ai_tool_utils.dart            # 公共辅助（不分类）
```

## 不变量
- `AiSessionController` 是状态机心脏；外部禁止旁路修改 session 状态，必须经 controller 公开方法。
- `_ai_session_*.part.dart` 与 `ai_session_controller.dart` 共生：必须同目录、`part of` 引用同文件名。
- `ai_module.dart` 的 bootstrap 是单飞：跨 isolate / 多实例化未经验证。
- service/<sub>/ 与 tools/<sub>/ 是组织约定，不引入额外抽象层；同 sub 内 peer 互相 bare-import，跨 sub 走 `'../<peer_sub>/X.dart'`。

## 跨 feature 依赖
- 入向：hooks executor / skills dir / memory controller provider 通过 `AiModule.bootstrap()` 注入
- 出向（通过对应 sibling 的 barrel）：mcp / memory / skills / harness / crons

## 拆分边界
- `service/` 与 `tools/` 已按职责分层；新增能力优先落到对应子目录。
- `ai_session_controller.dart` 仍是会话状态机入口；继续拆分前需先补齐会话 fixture 回归测试。
