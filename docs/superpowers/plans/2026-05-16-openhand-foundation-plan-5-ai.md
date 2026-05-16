# OpenHand P1 features/ai 拆解 · Plan-5

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development。
> Plan-5 是 P1 阶段，比 P0 任意 plan 都重；不能一次过。本文档将其拆为 5 个独立可交付的 Task。

**Goal:** 把 `lib/features/ai/`（108 文件 / 6.2 万行）从巨型 feature 拆为可维护的层次结构，建立 barrel，让 sibling 不再深路径 import。

**Architecture:** 不在本 Plan 内切分 `ai_session_controller.dart`（8870 行）— 该 controller 是状态机心脏，切之前需要先做 fixture 冻结测试（独立 Plan-7）。Plan-5 只做安全的「橱柜整理」：服务/工具按职责分类、建 barrel、sweep 调用方。

**前置：** P0 Plan-1/2/3/4 全部完成（HEAD `59af3ae` 及之后）。

参考：
- 设计：`docs/superpowers/specs/2026-05-16-openhand-foundation-design.md`
- 模板：Plan-3 mcp 是最近一个 controller-bearing 试点

---

## ai 现状摸底（2026-05-16）

```
lib/features/ai/
  ai_session_controller.dart        8870 行 ← 状态机心脏，本 Plan 不动
  _ai_session_models.dart           77 行   ← part-of 子片段
  _ai_session_utils.dart            587 行  ← part-of 子片段
  data/                             1 文件（ai_session_store.dart）
  model/                            19 文件（领域模型）
  service/                          55 文件（43 根 + web_fetch/ + web_search/ 子目录）
  tools/                            30 文件
```

`service/` 内 43 根级文件按职责粗分：
- **chat/protocol**：ai_chat_service, ai_protocol_adapter, ai_transport_diagnostic_messages
- **prompt**：ai_prompt_builder, ai_prompt_template_repository, machine_expert_prompts, programming_expert_prompts
- **tool runtime**：ai_tool_execution_registry, ai_tool_runtime_service, ai_plan_approval_detector
- **dsml**：ai_dsml_partial_stream_scanner, ai_dsml_tool_call_parser
- **file ops**：ai_file_history_service, ai_file_mutation_ledger, ai_file_tracker_service, ai_attachment_service
- **bash/sandbox**：ai_bash_tool_service, ai_sandbox_service, ai_sandbox_proxy_service
- **git**：ai_git_snapshot_service
- **lsp**：ai_lsp_managed_install_service, lsp_client_service
- **media**：ai_image_generation_service, ai_image_summary_extractor, media_cache_service
- **self_learning**：self_learning_dispatcher, self_learning_runner, self_learning_scheduler
- **claude_hook**：ai_claude_hook_service
- **session io**：ai_session_jsonl_exporter, ai_token_usage_parser
- **workspace**：ai_workspace_instruction_service
- **model registry**：ai_model_scanner
- **mcp bridge**：mcp_loaded_tools_tracker
- **web engine 基础**：web_engine_base, web_engine_cache_store_base, web_engine_concurrency, web_engine_http_exception, web_engine_json_utils, web_engine_quality, web_engine_telemetry_store_base
- **web_fetch/** 子目录
- **web_search/** 子目录

`tools/` 内 30 文件按工具类型粗分：
- **fs**：ai_read_tool, ai_write_tool, ai_edit_tool, ai_multi_edit_tool, ai_delete_file_tool, ai_glob_tool, ai_ls_tool, ai_file_read_renderer, ai_apply_file_diffs_tool, ai_notebook_edit_tool
- **bash**：ai_bash_tool, ai_bash_background_tool
- **search**：ai_grep_tool, ai_codebase_search_tool, ai_tool_search_tool
- **web**：ai_web_fetch_tool, ai_web_search_tool
- **lsp**：ai_lsp_tool, ai_read_lints_tool
- **git**：ai_git_tool
- **planning**：ai_exit_plan_mode_tool, ai_todo_write_tool, ai_task_tool, ai_ask_user_choice_tool
- **memory**：ai_memory_tool
- **skill**：ai_skill_manager_tool
- **registry & support**：ai_tool.dart（基类）、ai_tool_registry, ai_tool_execution_context, ai_tool_utils

main.dart imports 9 个 ai 文件：
- ai_session_controller, ai_chat_service, ai_claude_hook_service, ai_protocol_adapter, lsp_client_service, self_learning_dispatcher/runner/scheduler, web_fetch_cache_store, web_search_cache_store

---

## Task 1: barrel + AiModule（基础设施）

**目标：** 建立 `features/ai/index.dart` 与 `ai_module.dart`，main.dart 改走 module bootstrap。controller/service/tools/model 物理位置先不动。

**Steps：**

1. **AiModule shape**：阅读 main.dart L178-228 看 `AiSessionController.create(...)` 的注入依赖，写：
   ```dart
   class AiModule {
     AiModule._({required this.controller});
     final AiSessionController controller;
     static Future<AiModule> bootstrap({...原 create 参数...}) async {
       final controller = await AiSessionController.create(...);
       return AiModule._(controller: controller);
     }
     static List<SingleChildWidget> providers(AiModule m) => [
       ChangeNotifierProvider<AiSessionController>.value(value: m.controller),
     ];
   }
   ```

2. **index.dart barrel**：
   - Controller / Module export
   - service 中 sibling features 实际用到的：`ai_chat_service`, `ai_claude_hook_service`, `ai_protocol_adapter`, `ai_bash_tool_service`, `ai_image_generation_service`, `ai_tool_execution_registry`, `ai_tool_runtime_service`, `ai_transport_diagnostic_messages`, `mcp_loaded_tools_tracker`, `lsp_client_service`, `self_learning_dispatcher/runner/scheduler`, `web_fetch/web_fetch_cache_store`, `web_search/web_search_cache_store`
   - model 中外部使用的：`ai_thread_template`, `ai_session_runtime_context`, `ai_session_message`, `ai_session`, `ai_model_config`
   - 这里 export 数量较多 — 但宽 barrel 比窄 barrel 安全（再窄留给 P1-extension）

3. **main.dart wire**：换 import，走 `AiModule.bootstrap(...)` 并保留原有并行 future 启动顺序。

4. **commit**：`P0 plan-5 task 1 ai feature 建 barrel + AiModule（不动物理结构）`

---

## Task 2: caller sweep（最大违规削减）

**目标：** 把 sibling features 对 ai/* 的深路径 import 全部切到 `ai/index.dart` barrel。

**预期命中（按 check_imports）：**
- features/mcp/service/{mcp_lazy_loading_applier, mcp_tool_discovery_service, tool_search_history_serializer}.dart
- features/mcp/widgets/tool_search_loaded_dialog.dart
- features/message_gateway/{message_gateway_controller, service/web_message_platform_service}.dart
- features/crons/crons_controller.dart（如果有引用 ai）
- features/hardness/widgets/hardness_session_dashboard.*.part.dart（dashboard 显示 ai 工具 trace）
- features/home/openhand_home_page.dart 与 _home_*.dart

**Steps：** 逐文件 `grep -n "features/ai\|\.\./ai/" lib/features/<other>/...` 然后替换 import 块为 barrel。

**check_imports 预期：** 130 → 大幅下降（多数 ai-related 都是从 sibling 引发）。

**commit：** `P0 plan-5 task 2 ai barrel caller sweep`

---

## Task 3: service/ 子目录归类

**目标：** 43 根级 service 文件按职责分类到 service 子目录。**不改 import**（先批量 git mv，再批量 sed 一次性更新）。

**子目录：**
```
service/
  chat/        # ai_chat_service, ai_protocol_adapter, ai_transport_diagnostic_messages
  prompt/      # ai_prompt_builder, ai_prompt_template_repository, machine_expert_prompts, programming_expert_prompts
  runtime/     # ai_tool_execution_registry, ai_tool_runtime_service, ai_plan_approval_detector
  dsml/        # ai_dsml_*.dart
  fs/          # ai_file_*, ai_attachment_service
  bash/        # ai_bash_tool_service
  sandbox/     # ai_sandbox_*
  git/         # ai_git_snapshot_service
  lsp/         # ai_lsp_managed_install_service, lsp_client_service
  media/       # ai_image_*, media_cache_service
  self_learning/  # self_learning_*
  hook/        # ai_claude_hook_service
  session_io/  # ai_session_jsonl_exporter, ai_token_usage_parser
  workspace/   # ai_workspace_instruction_service
  model_registry/  # ai_model_scanner
  mcp_bridge/  # mcp_loaded_tools_tracker
  web_engine/  # web_engine_base, web_engine_cache_store_base, web_engine_concurrency, web_engine_http_exception, web_engine_json_utils, web_engine_quality, web_engine_telemetry_store_base
  web_fetch/   # 已是子目录，保留
  web_search/  # 已是子目录，保留
```

**Steps：**
1. mkdir 所有新子目录
2. `git mv` 每个根级 service 文件到对应子目录
3. 批量 sed 把 `'service/<file>.dart'` 改为 `'service/<subdir>/<file>.dart'` — 对全 lib 跑
4. 同时 service 内文件间相互 import 也要按新路径更新 — 这是 sed 重头戏
5. `flutter analyze` 0 errors 兜底
6. ai/index.dart barrel 内的 service export 路径同步更新

**commit：** `P0 plan-5 task 3 ai/service 按职责分 19 子目录`

---

## Task 4: tools/ 子目录归类

**目标：** 30 个 tool 文件按工具类型归类。

**子目录：**
```
tools/
  fs/         # read, write, edit, multi_edit, delete, glob, ls, file_read_renderer, apply_file_diffs, notebook_edit
  bash/       # bash, bash_background
  search/     # grep, codebase_search, tool_search
  web/        # web_fetch, web_search
  lsp/        # lsp, read_lints
  git/        # git
  planning/   # exit_plan_mode, todo_write, task, ask_user_choice
  memory/     # memory
  skill/      # skill_manager
  // 基础设施留在 tools/ 根：ai_tool.dart, ai_tool_registry.dart, ai_tool_execution_context.dart, ai_tool_utils.dart
```

**Steps：**
1. mkdir 子目录
2. git mv
3. 批量 sed 修同 feature 内引用
4. 更新 ai_tool_registry 中工具注册的 import
5. flutter analyze 0 errors
6. ai/index.dart barrel 中工具相关 export（如有）路径同步

**commit：** `P0 plan-5 task 4 ai/tools 按类型分 9 子目录`

---

## Task 5: 最终验收 + README

**Steps：**
1. `flutter analyze` 0 errors
2. `dart test scripts/test/` 6/6 PASS
3. `dart run scripts/check_imports.dart` 削减幅度
4. `bash scripts/build_web.sh`（SKIP_IMPORT_CHECK=1）通过
5. 写 `lib/features/ai/README.md`，列出：
   - feature 形态：controller-bearing，但 controller 8870 行待 P1-extension 拆
   - 子目录组织（service/ × 19，tools/ × 9）
   - barrel 入口 + main.dart 装配链
   - 不变量：`AiSessionController` 是状态机心脏，禁止旁路修改 session 状态；任何状态变更必经 controller 公开方法
6. 收尾 commit + roadmap 更新（标注 P1 已完 4/5，剩 ai_session_controller 拆给 P1-extension Plan-7）

**commit：** `P0 plan-5 完成：ai feature 整理（不含 controller 拆分）`

---

## P1-extension（Plan-7，留待后续）

不在本 Plan：
- 拆 `ai_session_controller.dart` 8870 行 → 多个 sub-controller 或 part-files
- 拆 `_ai_session_models.dart` / `_ai_session_utils.dart` 是否仍合理
- 需先做 fixture 冻结测试：抓 10 条 representative session trace，作为拆解前后等价性 oracle

---

## 风险点

| 风险 | 缓解 |
|---|---|
| 43 service 文件相互 import 错综复杂，sed 后可能漏改 | 每个 git mv 批次后立即 flutter analyze；分批小步推 |
| ai_session_controller 内部对 service/tools 的 import 路径变多 | 该 file 不动；sed 全局更新会同步它的 import 段 |
| tool registry 在 service 与 tools 之间桥接 | 保留 tools 根级的 ai_tool_registry.dart 与 ai_tool.dart；这是「公共基础」不分类 |
| ai_session_controller.dart 内部有 `part '_ai_session_*.dart'` | part of 引用保留同 feature 根目录，不动 _ai_session_*.dart 位置 |
